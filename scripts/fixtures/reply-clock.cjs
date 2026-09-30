// 只替代计时器边界；测试中的阶段和消息来自真实生产控制器。
function replyClock() {
  let now = 0, sequence = 0;
  const pending = new Map(), all = new Map();
  const scheduler = {
    schedule(callback, delayMs) {
      const id = ++sequence;
      pending.set(id, { callback, due: now + delayMs }); all.set(id, callback);
      return id;
    },
    clear(id) { pending.delete(id); }
  };
  function advance(milliseconds) {
    const limit = now + milliseconds;
    let rounds = 0;
    while (pending.size > 0) {
      const [id, job] = [...pending.entries()].sort((a, b) => a[1].due - b[1].due)[0];
      if (job.due > limit) break;
      if (++rounds > 1000) throw new Error('计时器没有结束');
      pending.delete(id); now = job.due; job.callback();
    }
    now = limit;
  }
  return { scheduler, advance,
    drain() { while (pending.size > 0) advance(Math.min(...[...pending.values()].map(job => job.due)) - now); },
    stale(id) { all.get(id)(); }, ids: () => [...pending.keys()], count: () => pending.size, now: () => now };
}
module.exports = { replyClock };
