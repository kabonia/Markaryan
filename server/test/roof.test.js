import test from 'node:test';
import assert from 'node:assert/strict';
import { homography, apply, gableGeometry, combine } from '../src/roof.js';

// Синтетический дом: торец 8 м, карниз 3 м, конёк 6 м → уклон atan(3/4) = 36,87°. Снят с ракурсом (перспектива).
const P = [[90, 12, 150], [-4, -85, 900], [0.004, 0.006, 1]];
const toPhoto = ([x, y]) => { const [u, v] = apply(P, [x, y]); return [u / (4 / 3), v]; };
const photo = {
  wallBottomLeft: toPhoto([0, 0]), wallBottomRight: toPhoto([8, 0]), eaveRight: toPhoto([8, 3]), eaveLeft: toPhoto([0, 3]),
  apex: toPhoto([4, 6]), doorBottom: toPhoto([2, 0]), doorTop: toPhoto([2, 2.05]), frontal: true,
};

test('гомография переносит точки точно', () => {
  const H = homography([[0, 0], [1, 0], [1, 1], [0, 1]], [[10, 10], [30, 12], [28, 40], [8, 35]]);
  assert.deepEqual(apply(H, [1, 1]).map((v) => Math.round(v)), [28, 40]);
});

test('по замерам: уклон и конёк точно, несмотря на ракурс', () => {
  const g = gableGeometry(photo, { width: 8, eave: 3 });
  assert.equal(g.pitchDeg, 36.9);
  assert.equal(g.ridgeHeight, 6);
  assert.equal(g.scaleSource, 'measured');
  assert.ok(g.symmetric);
});

test('по двери: масштаб-предположение', () => {
  const g = gableGeometry(photo, {});
  assert.equal(g.scaleSource, 'assumption');
  assert.ok(Math.abs(g.ridgeHeight - 6) < 1.5);
});

test('свод: метки достоверности', () => {
  const out = combine({ roofType: 'gable', photos: [photo], estimate: { overhang: 0.5 } }, { gableWidth: 8, eaveHeight: 3 });
  assert.equal(out.gableWidth.source, 'measured');
  assert.equal(out.ridgeHeight.source, 'photo');
  assert.equal(out.ridgeHeight.value, 6);
  assert.equal(out.overhang.source, 'assumption');
});
