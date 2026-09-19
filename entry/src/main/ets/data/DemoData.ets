import { Category, DemoSnapshot, Garment, GarmentStatus, emptyProfile, emptyMembership,
  emptyBodyProfile } from '../model/Wardrobe';

// 仅图片为素材照片；温度区间、场合、穿着次数与偏好属性都是演示参数，后续由用户确认值替代。
// 偏好属性（版型、配色、风格、叠穿、图案）用于按偏好档案调整推荐顺序，不参与硬过滤。
export function demoGarments(): Garment[] {
  return [
    { id: 'tee', name: '白色圆领短袖', category: Category.TOP, imageKey: 'tee', imageUri: '', color: '白色',
      minTemp: 16, maxTemp: 35, occasions: ['上课', '社团', '约会'], status: GarmentStatus.READY, wearCount: 12, isDemo: true,
      fit: '合身', palette: '基础色', style: '简约', layering: false, pattern: false },
    { id: 'shirt', name: '蓝色印花衬衫', category: Category.TOP, imageKey: 'shirt', imageUri: '', color: '蓝色',
      minTemp: 12, maxTemp: 29, occasions: ['上课', '课程展示', '约会'], status: GarmentStatus.READY, wearCount: 6, isDemo: true,
      fit: '宽松', palette: '低饱和', style: '学院', layering: true, pattern: true },
    { id: 'jeans', name: '日常牛仔裤', category: Category.BOTTOM, imageKey: 'jeans', imageUri: '', color: '蓝色',
      minTemp: 8, maxTemp: 30, occasions: ['上课', '课程展示', '社团', '约会'], status: GarmentStatus.READY, wearCount: 18, isDemo: true,
      fit: '合身', palette: '基础色', style: '简约', layering: false, pattern: false },
    { id: 'shoes', name: '棕色休闲运动鞋', category: Category.SHOES, imageKey: 'shoes', imageUri: '', color: '棕色',
      minTemp: 5, maxTemp: 35, occasions: ['上课', '课程展示', '社团', '约会'], status: GarmentStatus.READY, wearCount: 24, isDemo: true,
      fit: '合身', palette: '基础色', style: '运动', layering: false, pattern: false },
    { id: 'jacket', name: '黑色短款皮夹克', category: Category.OUTER, imageKey: 'jacket', imageUri: '', color: '黑色',
      minTemp: 8, maxTemp: 22, occasions: ['上课', '课程展示', '社团', '约会'], status: GarmentStatus.READY, wearCount: 4, isDemo: true,
      fit: '有轮廓感', palette: '基础色', style: '复古', layering: true, pattern: false },
    { id: 'graphic', name: '米白印花短袖', category: Category.TOP, imageKey: 'graphic', imageUri: '', color: '米白色',
      minTemp: 18, maxTemp: 35, occasions: ['上课', '社团', '约会'], status: GarmentStatus.LAUNDRY, wearCount: 7, isDemo: true,
      fit: '宽松', palette: '明亮', style: '运动', layering: false, pattern: true }
  ];
}

export function initialSnapshot(): DemoSnapshot {
  return { version: 1, garments: demoGarments(), saved: [], records: [], occasion: '上课', temperature: 24,
    activeIds: ['tee', 'jeans', 'shoes'], profile: emptyProfile(),
    diary: [], tryOnTasks: [], membership: emptyMembership(), body: emptyBodyProfile(), city: '湖州市' };
}
