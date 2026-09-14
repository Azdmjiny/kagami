import { readFileSync, writeFileSync } from "node:fs";

const variants = [
  ["icp4", "icon_16x16.png"],
  ["icp5", "icon_32x32.png"],
  ["icp6", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic08", "icon_256x256.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
];

const chunks = variants.map(([type, filename]) => {
  const image = readFileSync(new URL(`./AppIcon.iconset/${filename}`, import.meta.url));
  const header = Buffer.alloc(8);
  header.write(type, 0, 4, "ascii");
  header.writeUInt32BE(image.length + 8, 4);
  return Buffer.concat([header, image]);
});
const header = Buffer.alloc(8);
header.write("icns", 0, 4, "ascii");
header.writeUInt32BE(8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0), 4);
writeFileSync(new URL("./Kagami.icns", import.meta.url), Buffer.concat([header, ...chunks]));
