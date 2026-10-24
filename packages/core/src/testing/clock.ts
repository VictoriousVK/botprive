/** Horloge contrôlable : permet de « voyager dans le temps » dans les tests. */
export class TestClock {
  private current: Date;
  constructor(start: Date | string) {
    this.current = new Date(start);
  }
  now = (): Date => new Date(this.current);
  set(date: Date | string): void {
    this.current = new Date(date);
  }
  advanceMinutes(minutes: number): void {
    this.current = new Date(this.current.getTime() + minutes * 60_000);
  }
  advanceDays(days: number): void {
    this.current = new Date(this.current.getTime() + days * 86_400_000);
  }
}
