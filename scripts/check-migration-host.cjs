const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Module = require('node:module');

// 用最小文件系统替身验证 Host 的边界，不模拟设备 Picker 的真实 UI。
const files = new Map();
const handles = new Map();
let nextFd = 10;
let failWrite = false;
let pickerSaveUris = [];
let pickerSelectUris = [];
const pngBytes = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4]);
const largePngBytes = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4, 5]);

function pathOf(value) {
  if (typeof value !== 'string') throw new Error('path required');
  return value.startsWith('file://') ? value.slice('file://'.length) : value;
}

function stubFileIo() {
  const OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, NOFOLLOW: 262144 };
  return {
    OpenMode,
    async open(value, mode) {
      const path = pathOf(value);
      const writable = (mode & OpenMode.WRITE_ONLY) !== 0 || (mode & OpenMode.READ_WRITE) !== 0;
      if (!files.has(path) && !writable) throw new Error('missing');
      if (!files.has(path) && (mode & OpenMode.CREATE) !== 0) files.set(path, new Uint8Array());
      if (!files.has(path)) throw new Error('missing');
      if ((mode & OpenMode.TRUNC) !== 0) files.set(path, new Uint8Array());
      const fd = nextFd++;
      handles.set(fd, { path, offset: 0 });
      return { fd, path };
    },
    async close(file) { handles.delete(typeof file === 'number' ? file : file.fd); },
    async stat(value) {
      const fd = typeof value === 'number' ? value : undefined;
      const path = fd === undefined ? pathOf(value) : handles.get(fd).path;
      if (!files.has(path)) throw new Error('missing');
      return { size: files.get(path).length };
    },
    accessSync(value) { return files.has(pathOf(value)); },
    async read(fd, buffer, options = {}) {
      const handle = handles.get(fd);
      const bytes = files.get(handle.path);
      const length = Math.min(options.length || buffer.byteLength, bytes.length - handle.offset);
      if (length <= 0) return 0;
      new Uint8Array(buffer, 0, length).set(bytes.slice(handle.offset, handle.offset + length));
      handle.offset += length;
      return length;
    },
    async write(fd, buffer) {
      if (failWrite) throw new Error('injected write failure');
      const handle = handles.get(fd);
      const input = new Uint8Array(buffer);
      const before = files.get(handle.path);
      const output = new Uint8Array(Math.max(before.length, handle.offset + input.length));
      output.set(before);
      output.set(input, handle.offset);
      files.set(handle.path, output);
      handle.offset += input.length;
      return input.length;
    },
    async fsync() {},
    async unlink(value) { files.delete(pathOf(value)); },
    async rename(oldValue, newValue) {
      const oldPath = pathOf(oldValue);
      const newPath = pathOf(newValue);
      files.set(newPath, files.get(oldPath));
      files.delete(oldPath);
    }
  };
}

const stubFileUri = {
  FileUri: class {
    constructor(value) { this.path = pathOf(value); }
  },
  getUriFromPath(path) { return 'file://' + path; }
};

class StubPicker {
  constructor() {}
  async save() { return pickerSaveUris.slice(); }
  async select() { return pickerSelectUris.slice(); }
}

class StubSaveOptions {}
class StubSelectOptions {}

const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@kit.AbilityKit') return { common: {} };
  if (request === '@kit.ArkTS') {
    return {
      util: {
        TextEncoder: class { encodeInto(value) { return new global.TextEncoder().encode(value); } },
        TextDecoder: { create: (encoding, options) => {
          const decoder = new global.TextDecoder(encoding, options);
          return { decodeToString(value) { return decoder.decode(value); } };
        } }
      }
    };
  }
  if (request === '@kit.CoreFileKit') return { fileIo: stubFileIo(), fileUri: stubFileUri,
    picker: { DocumentViewPicker: StubPicker, DocumentSaveOptions: StubSaveOptions, DocumentSelectOptions: StubSelectOptions } };
  return originalLoad.call(this, request, parent, isMain);
};

const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const host = require('../entry/src/main/ets/service/WardrobeMigrationHost.ets');

test('source adapter 只读取 filesDir 内、大小合法的完整字节', async () => {
  files.set('/app/files/shirt.png', pngBytes);
  const adapters = host.createCoreFileMigrationAdapters('/app/files', { maxImageBytes: pngBytes.length });
  assert.equal(adapters.source.isPrivateUri('file:///app/files/shirt.png'), true);
  assert.equal(adapters.source.isPrivateUri('file:///other/shirt.png'), false);
  assert.deepEqual(Array.from(await adapters.source.read('file:///app/files/shirt.png')), Array.from(pngBytes));
  await assert.rejects(adapters.source.read('file:///other/shirt.png'), /filesDir/);
  files.set('/app/files/large.png', largePngBytes);
  await assert.rejects(adapters.source.read('file:///app/files/large.png'), /超过上限/);
});

test('target adapter 使用 garment_batch 前缀、唯一文件名且成功写入后保留文件', async () => {
  const target = host.createCoreFileMigrationTargetAdapter('/app/files', { maxImageBytes: pngBytes.length });
  const uri = target.destinationUri('asset-0', 'phone-a:3:abcd');
  assert.match(uri, /file:\/\/\/app\/files\/garment_batch_migration_/);
  await target.write(uri, pngBytes);
  assert.deepEqual(Array.from(files.get(pathOf(uri))), Array.from(pngBytes));
  await assert.rejects(target.write(uri, pngBytes.slice(0, 1)), /已存在|覆盖|PNG/);
  await target.remove(uri);
  assert.equal(files.has(pathOf(uri)), false);
});

test('target 写入失败会清理半成品，非法路径和非迁移文件不能删除', async () => {
  const target = host.createCoreFileMigrationTargetAdapter('/app/files', { maxImageBytes: pngBytes.length });
  const uri = target.destinationUri('asset-1', 'phone-a');
  failWrite = true;
  await assert.rejects(target.write(uri, pngBytes), /failure|写入/);
  failWrite = false;
  assert.equal(files.has(pathOf(uri)), false);
  await assert.rejects(target.write('file:///app/other.bin', Uint8Array.from([1])), /filesDir/);
  await assert.rejects(target.remove('file:///app/files/user.png'), /迁移文件/);
});

test('DocumentViewPicker 取消明确返回 cancelled，成功导出文件不会被 finally 删除', async () => {
  pickerSaveUris = [];
  const cancelled = await host.saveMigrationPackageWithPicker({}, '{"ok":true}', 'test');
  assert.equal(cancelled.status, 'cancelled');

  const uri = 'file:///picker/test.yida';
  files.set('/picker/test.yida', new Uint8Array());
  pickerSaveUris = [uri];
  const saved = await host.saveMigrationPackageWithPicker({}, '{"ok":true}', 'test');
  assert.equal(saved.status, 'saved');
  assert.equal(new TextDecoder().decode(files.get('/picker/test.yida')), '{"ok":true}');
  pickerSelectUris = [];
  const importCancelled = await host.selectMigrationPackageWithPicker({});
  assert.equal(importCancelled.status, 'cancelled');
});

test('Picker 读取也限制完整 UTF-8 包大小', async () => {
  files.set('/picker/input.yida', Uint8Array.from(new TextEncoder().encode('{"input":true}')));
  pickerSelectUris = ['file:///picker/input.yida'];
  const selected = await host.selectMigrationPackageWithPicker({}, { maxPickerPackageBytes: 100 });
  assert.equal(selected.status, 'selected');
  assert.equal(selected.value, '{"input":true}');
  const tooSmall = await host.selectMigrationPackageWithPicker({}, { maxPickerPackageBytes: 2 });
  assert.equal(tooSmall.status, 'failed');
  assert.match(tooSmall.message, /超过上限/);
});
