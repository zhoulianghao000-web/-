/** Money is stored in integer fen; do not divide into a floating point yuan value. */
export function analyticsMoney(fen:number):string {
  if(!Number.isSafeInteger(fen))throw new RangeError('Invalid integer fen');
  const absolute=Math.abs(fen);
  return `¥${fen<0?'-':''}${Math.floor(absolute/100)}.${String(absolute%100).padStart(2,'0')}`;
}
