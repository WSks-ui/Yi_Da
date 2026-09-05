export class GarmentRoute {
  id: string;
  space: string;

  constructor(id: string = '', space: string = 'personal') {
    this.id = id;
    this.space = space;
  }
}
