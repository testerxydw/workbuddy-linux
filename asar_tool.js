const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Electron C++ asar 格式（pickle 前缀）:
//   offset 0:  uint32 P0 = 4
//   offset 4:  uint32 P1 = ceil4(H) + 8
//   offset 8:  uint32 P2 = ceil4(H) + 4
//   offset 12: uint32 P3 = H (JSON header 长度)
//   offset 16: JSON header (H 字节)
//   padding 到 4 字节对齐
//   dataStart = 16 + ceil4(H)
//   file 数据: offset 相对 dataStart

function extract(archive, dest) {
  const fd = fs.openSync(archive, 'r');
  const stat = fs.fstatSync(fd);
  const head = Buffer.alloc(16);
  fs.readSync(fd, head, 0, 16, 0);
  const headerSize = head.readUInt32LE(12);
  const jb = Buffer.alloc(headerSize);
  fs.readSync(fd, jb, 0, headerSize, 16);
  const header = JSON.parse(jb.toString('utf8'));
  const dataStart = 16 + Math.ceil(headerSize / 4) * 4;
  fs.mkdirSync(dest, { recursive: true });
  let n = 0;
  function walk(o, dir) {
    for (const name in o) {
      const e = o[name];
      const out = path.join(dir, name);
      if (e.files) { fs.mkdirSync(out, { recursive: true }); walk(e.files, out); }
      else if (e.link !== undefined) {
        fs.mkdirSync(path.dirname(out), { recursive: true });
        try { fs.unlinkSync(out); } catch (x) {}
        fs.symlinkSync(e.link, out);
      } else if (typeof e.size === 'number') {
        if (!e.unpacked) {
          fs.mkdirSync(path.dirname(out), { recursive: true });
          const size = e.size || 0;
          const off = Number(e.offset || 0);
          if (size > 0) {
            const buf = Buffer.alloc(size);
            fs.readSync(fd, buf, 0, size, dataStart + off);
            fs.writeFileSync(out, buf);
          } else fs.writeFileSync(out, Buffer.alloc(0));
          n++;
        }
      }
    }
  }
  walk(header.files, dest);
  fs.closeSync(fd);
  fs.writeFileSync(dest + '.header.json', JSON.stringify(header));
  console.log('EXTRACT_OK 内部文件=' + n);
}

function pack(src, archive) {
  const header = JSON.parse(fs.readFileSync(src + '.header.json', 'utf8'));
  const writes = [];
  function walk(o, dir) {
    for (const name in o) {
      const e = o[name];
      const dp = path.join(dir, name);
      if (e.files) walk(e.files, dp);
      else if (typeof e.size === 'number') {
        if (!e.unpacked) { e.size = fs.statSync(dp).size; writes.push({ e, dp }); }
      }
    }
  }
  walk(header.files, src);
  let off = 0;
  for (const w of writes) {
    w.e.offset = String(off);
    off += w.e.size;
    if (w.e.integrity) {
      const b = fs.readFileSync(w.dp);
      w.e.integrity = { algorithm: 'SHA256', hash: crypto.createHash('sha256').update(b).digest('base64') };
    }
  }
  const json = JSON.stringify(header);
  const H = Buffer.byteLength(json);
  const pad = (4 - (H % 4)) % 4;
  const c4 = H + pad;
  const prefix = Buffer.alloc(16);
  prefix.writeUInt32LE(4, 0);
  prefix.writeUInt32LE(c4 + 8, 4);
  prefix.writeUInt32LE(c4 + 4, 8);
  prefix.writeUInt32LE(H, 12);
  const out = fs.openSync(archive, 'w');
  fs.writeSync(out, prefix, 0, 16, 0);
  fs.writeSync(out, Buffer.from(json, 'utf8'), 0, H, 16);
  if (pad > 0) fs.writeSync(out, Buffer.alloc(pad), 0, pad, 16 + H);
  let pos = 16 + H + pad;
  for (const w of writes) {
    const b = fs.readFileSync(w.dp);
    fs.writeSync(out, b, 0, b.length, pos);
    pos += b.length;
  }
  fs.closeSync(out);
  console.log('PACK_OK bytes=' + pos + ' 内部文件=' + writes.length);
}

const mode = process.argv[2];
const a = process.argv[3];
const b = process.argv[4];
if (mode === 'extract') extract(a, b);
else if (mode === 'pack') pack(a, b);
else { console.error('usage: node asar_tool.js extract|pack <archive> <dir>'); process.exit(1); }
