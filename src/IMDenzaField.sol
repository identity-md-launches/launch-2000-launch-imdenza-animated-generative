// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMDenzaField
/// @notice Deterministic flow-field tracer: grows thick curved strokes ("rectangles") along a
///         noise-perturbed vector field with collision control, and writes them as SVG.
/// @dev    Pure and seeded: the same `Params` always yield byte-identical output. All maths is
///         integer fixed-point. Canvas is 1000x1000 user units; shapes may start outside it.
///         Output is split in two strings so the caller can place `<path>` definitions in
///         `<defs>` and the `<use>` instances (with per-shape colour / animation variables) after.
contract IMDenzaField {
    struct Params {
        bytes32 seed; // composition seed
        uint16 attempts; // shape attempts
        uint16 maxSteps; // max points per shape
        uint16 stepLen; // canvas units per step
        uint16 minThick; // min stroke width
        uint16 maxThick; // max stroke width
        uint16 turb; // angle swing in brads (1024 = full turn) applied to noise
        uint16 noiseCell; // noise lattice cell size (canvas units), >= 32
        uint16 baseAngle; // field base angle in brads
        uint16 gap; // collision gap in canvas units
        uint16 thickVar; // breathing amplitude in percent
        uint16 speed; // 100 = base animation speed, 200 = twice as fast
        uint16 flowAmp; // flow translation amplitude in canvas units (x10)
        bool outline; // draw an outline pass under each shape
    }

    struct Buf {
        bytes data;
        uint256 len;
    }

    struct Rng {
        uint256 state;
        uint256 bits;
        uint256 left;
    }

    struct Ctx {
        uint256[96] grid; // occupancy, 16-unit cells, 96x96 covering -256..1280
        uint256[] lattice; // noise lattice, one value (0..1023) per word
        uint256 nx; // lattice columns
        int256[] px; // scratch points
        int256[] py;
    }

    uint256 private constant GRID_CELL = 16;
    uint256 private constant MAX_TRIES = 1200;
    int256 private constant GRID_OFFSET = 256;
    int256 private constant BOUND = 1240;

    /// @notice Trace the field and write SVG.
    /// @param p       Field parameters.
    /// @param palette 7 stroke colours followed by 1 outline colour, 3 bytes each (24 bytes).
    /// @return defs   `<path id=.. d=..>` elements, to be placed inside `<defs>`.
    /// @return uses   `<use>` elements referencing them, in paint order.
    /// @return count  Number of shapes drawn.
    function render(Params memory p, bytes memory palette)
        external
        pure
        returns (string memory defs, string memory uses, uint256 count)
    {
        require(palette.length == 24, "palette");
        require(p.noiseCell >= 32 && p.stepLen >= 4 && p.maxSteps >= 3 && p.maxThick >= p.minThick, "params");

        Rng memory rng = Rng(uint256(p.seed), 0, 0);
        Ctx memory c;
        _lattice(c, p);
        c.px = new int256[](p.maxSteps);
        c.py = new int256[](p.maxSteps);

        Buf memory d = Buf(new bytes(uint256(p.attempts) * (uint256(p.maxSteps) * 14 + 40) + 64), 0);
        Buf memory u = Buf(new bytes(uint256(p.attempts) * 360 + 64), 0);

        uint256 rot = _next(rng) % 7; // palette rotation: a different dominant colour per piece
        // `attempts` bounds the shapes drawn; start points that land on occupied cells are cheap
        // misses, so up to MAX_TRIES candidate starts are examined to reach that bound.
        for (uint256 tries; tries < MAX_TRIES && count < p.attempts; ++tries) {
            uint256 n = _trace(c, p, rng);
            if (n < 3) continue;
            uint256 thick = p.minThick + _next(rng) % (uint256(p.maxThick) - p.minThick + 1);
            _mark(c, n, thick + p.gap);
            _writePath(d, count, n, c);
            _writeUse(u, p, rng, palette, count, thick, rot, c);
            ++count;
        }
        defs = _finish(d);
        uses = _finish(u);
    }

    // ---------------------------------------------------------------- field

    function _lattice(Ctx memory c, Params memory p) private pure {
        uint256 nx = 1536 / p.noiseCell + 2;
        c.nx = nx;
        uint256[] memory lat = new uint256[](nx * nx);
        for (uint256 i; i < lat.length; ++i) {
            lat[i] = uint256(keccak256(abi.encodePacked(p.seed, i))) & 1023;
        }
        c.lattice = lat;
    }

    /// @dev Value noise 0..1023 at canvas point (x, y), bilinear with smoothstep.
    function _noise(Ctx memory c, uint256 cell, int256 x, int256 y) private pure returns (uint256) {
        uint256 ax = uint256(x + GRID_OFFSET);
        uint256 ay = uint256(y + GRID_OFFSET);
        uint256 gx = ax / cell;
        uint256 gy = ay / cell;
        uint256 su = _smooth((ax % cell) * 1024 / cell);
        uint256 sv = _smooth((ay % cell) * 1024 / cell);
        uint256 nx = c.nx;
        uint256[] memory lat = c.lattice;
        uint256 v00;
        uint256 v10;
        uint256 v01;
        uint256 v11;
        require(gy * nx + gx + nx + 1 < lat.length, "lattice");
        assembly ("memory-safe") {
            let ptr := add(add(lat, 32), mul(add(mul(gy, nx), gx), 32))
            v00 := mload(ptr)
            v10 := mload(add(ptr, 32))
            ptr := add(ptr, mul(nx, 32))
            v01 := mload(ptr)
            v11 := mload(add(ptr, 32))
        }
        uint256 top = v00 * (1024 - su) + v10 * su;
        uint256 bot = v01 * (1024 - su) + v11 * su;
        return (top * (1024 - sv) + bot * sv) >> 20;
    }

    function _smooth(uint256 t) private pure returns (uint256) {
        // t in 0..1024 -> t*t*(3-2t) in 0..1024
        return (t * t * (3072 - 2 * t)) >> 20;
    }

    /// @dev Field angle in brads at (x, y).
    function _angle(Ctx memory c, Params memory p, int256 x, int256 y) private pure returns (uint256) {
        int256 n = int256(_noise(c, p.noiseCell, x, y)) - 512;
        int256 a = int256(uint256(p.baseAngle)) + (n * int256(uint256(p.turb))) / 1024;
        return uint256(a + 4096) & 1023;
    }

    /// @dev sin of angle in brads (1024 = full turn), scaled to -1000..1000 (Bhaskara approximation).
    function _sin(uint256 a) private pure returns (int256) {
        a &= 1023;
        bool neg = a >= 512;
        uint256 x = neg ? a - 512 : a;
        uint256 q = x * (512 - x);
        int256 s = int256((16000 * q) / (1310720 - 4 * q));
        return neg ? -s : s;
    }

    function _cos(uint256 a) private pure returns (int256) {
        return _sin(a + 256);
    }

    /// @dev Grow one stroke from a random start point. Returns number of points written to c.px/py.
    function _trace(Ctx memory c, Params memory p, Rng memory rng) private pure returns (uint256 n) {
        int256 x = (int256(_next(rng) % 1200) - 100) * 16;
        int256 y = (int256(_next(rng) % 1200) - 100) * 16;
        uint256 r = (uint256(p.maxThick) / 2 + p.gap + GRID_CELL / 2) / GRID_CELL + 1;
        int256 step = int256(uint256(p.stepLen)) * 16;
        for (; n < p.maxSteps; ++n) {
            int256 cx = x / 16;
            int256 cy = y / 16;
            if (cx < -BOUND + 1000 || cx > BOUND || cy < -BOUND + 1000 || cy > BOUND) break;
            if (_occupied(c, cx, cy, r)) break;
            c.px[n] = cx;
            c.py[n] = cy;
            uint256 a = _angle(c, p, cx, cy);
            x += (_cos(a) * step) / 1000;
            y += (_sin(a) * step) / 1000;
        }
    }

    function _cell(int256 v) private pure returns (uint256) {
        return uint256(v + GRID_OFFSET) / GRID_CELL;
    }

    function _occupied(Ctx memory c, int256 x, int256 y, uint256 r) private pure returns (bool) {
        uint256 gx = _cell(x);
        uint256 gy = _cell(y);
        uint256 x0 = gx > r ? gx - r : 0;
        uint256 x1 = gx + r > 95 ? 95 : gx + r;
        uint256 y0 = gy > r ? gy - r : 0;
        uint256 y1 = gy + r > 95 ? 95 : gy + r;
        uint256 mask = ((uint256(1) << (x1 - x0 + 1)) - 1) << x0;
        for (uint256 gy_ = y0; gy_ <= y1; ++gy_) {
            if (c.grid[gy_] & mask != 0) return true;
        }
        return false;
    }

    function _mark(Ctx memory c, uint256 n, uint256 thick) private pure {
        uint256 r = (thick / 2 + GRID_CELL / 2) / GRID_CELL;
        for (uint256 i; i < n; ++i) {
            uint256 gx = _cell(c.px[i]);
            uint256 gy = _cell(c.py[i]);
            uint256 x0 = gx > r ? gx - r : 0;
            uint256 x1 = gx + r > 95 ? 95 : gx + r;
            uint256 y0 = gy > r ? gy - r : 0;
            uint256 y1 = gy + r > 95 ? 95 : gy + r;
            uint256 mask = ((uint256(1) << (x1 - x0 + 1)) - 1) << x0;
            for (uint256 gy_ = y0; gy_ <= y1; ++gy_) {
                c.grid[gy_] |= mask;
            }
        }
    }

    // ---------------------------------------------------------------- svg

    function _writePath(Buf memory d, uint256 id, uint256 n, Ctx memory c) private pure {
        _w(d, '<path id="p');
        _wu(d, id);
        _w(d, '" d="M');
        _wi(d, c.px[0]);
        _w(d, " ");
        _wi(d, c.py[0]);
        _w(d, "L");
        for (uint256 i = 1; i < n; ++i) {
            _wi(d, c.px[i]);
            _w(d, " ");
            _wi(d, c.py[i]);
            if (i + 1 < n) _w(d, " ");
        }
        _w(d, '"/>');
    }

    function _writeUse(
        Buf memory u,
        Params memory p,
        Rng memory rng,
        bytes memory palette,
        uint256 id,
        uint256 thick,
        uint256 rot,
        Ctx memory c
    ) private pure {
        uint256 r = _next(rng);
        uint256 r2 = _next(rng);
        uint256 colour = (_weightedColour(r % 100) + rot) % 7;
        // Flow direction: along the stroke's own first segment, amplitude scaled by flowAmp.
        int256 dx = c.px[1] - c.px[0];
        int256 dy = c.py[1] - c.py[0];
        int256 len = _abs(dx) + _abs(dy);
        if (len == 0) len = 1;
        int256 amp = int256(uint256(p.flowAmp) * (50 + ((r >> 8) % 100)) / 100); // x10 units
        int256 fx = (dx * amp) / (len * 10);
        int256 fy = (dy * amp) / (len * 10);
        uint256 t = (6000 + (r2 % 8000)) * 100 / p.speed; // ms
        uint256 delay = (r2 >> 13) % 9000; // ms
        uint256 w2 = thick * (100 + p.thickVar) / 100;
        if (w2 == thick) w2 = thick + 1;

        if (p.outline) {
            _w(u, '<use href="#p');
            _wu(u, id);
            _w(u, '" class="o" stroke="#');
            _hex(u, palette, 7);
            _w(u, '" style="--w:');
            _wu(u, thick + 4 + thick / 10);
            _w(u, "px;--w2:");
            _wu(u, w2 + 4 + thick / 10);
            _w(u, "px;--x:");
            _wi(u, fx);
            _w(u, "px;--y:");
            _wi(u, fy);
            _w(u, "px;--t:");
            _ms(u, t);
            _w(u, ";--d:-");
            _ms(u, delay);
            _w(u, '"/>');
        }
        _w(u, '<use href="#p');
        _wu(u, id);
        if (id % 5 == 3) _w(u, '" class="s k" stroke="#');
        else _w(u, '" class="s" stroke="#');
        _hex(u, palette, colour);
        _w(u, '" style="--w:');
        _wu(u, thick);
        _w(u, "px;--w2:");
        _wu(u, w2);
        _w(u, "px;--x:");
        _wi(u, fx);
        _w(u, "px;--y:");
        _wi(u, fy);
        _w(u, "px;--t:");
        _ms(u, t);
        _w(u, ";--d:-");
        _ms(u, delay);
        _w(u, '"/>');
    }

    /// @dev Fidenza-like colour probability: one dominant colour, a few secondaries, rare accents.
    function _weightedColour(uint256 r) private pure returns (uint256) {
        if (r < 30) return 0;
        if (r < 50) return 1;
        if (r < 65) return 2;
        if (r < 77) return 3;
        if (r < 87) return 4;
        if (r < 95) return 5;
        return 6;
    }

    // ---------------------------------------------------------------- rng

    function _next(Rng memory r) private pure returns (uint256 v) {
        if (r.left == 0) {
            r.state = uint256(keccak256(abi.encode(r.state)));
            r.bits = r.state;
            r.left = 8;
        }
        v = r.bits & 0xffffffff;
        r.bits >>= 32;
        --r.left;
    }

    function _abs(int256 v) private pure returns (int256) {
        return v < 0 ? -v : v;
    }

    // ---------------------------------------------------------------- buffer

    function _w(Buf memory b, bytes memory s) private pure {
        uint256 l = s.length;
        uint256 len = b.len;
        bytes memory data = b.data;
        require(len + l <= data.length, "buf");
        assembly ("memory-safe") {
            mcopy(add(add(data, 32), len), add(s, 32), l)
        }
        b.len = len + l;
    }

    function _wu(Buf memory b, uint256 v) private pure {
        if (v == 0) {
            _w(b, "0");
            return;
        }
        uint256 digits;
        for (uint256 t = v; t != 0; t /= 10) {
            ++digits;
        }
        bytes memory data = b.data;
        uint256 len = b.len;
        require(len + digits <= data.length, "buf");
        assembly ("memory-safe") {
            let ptr := add(add(data, 32), add(len, digits))
            for {} 1 {} {
                ptr := sub(ptr, 1)
                mstore8(ptr, add(48, mod(v, 10)))
                v := div(v, 10)
                if iszero(v) { break }
            }
        }
        b.len = len + digits;
    }

    function _wi(Buf memory b, int256 v) private pure {
        if (v < 0) {
            _w(b, "-");
            _wu(b, uint256(-v));
        } else {
            _wu(b, uint256(v));
        }
    }

    /// @dev milliseconds -> "s.t" seconds with one decimal, plus unit.
    function _ms(Buf memory b, uint256 ms) private pure {
        _wu(b, ms / 1000);
        _w(b, ".");
        _wu(b, (ms % 1000) / 100);
        _w(b, "s");
    }

    function _hex(Buf memory b, bytes memory palette, uint256 idx) private pure {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(6);
        for (uint256 i; i < 3; ++i) {
            uint8 v = uint8(palette[idx * 3 + i]);
            out[i * 2] = alphabet[v >> 4];
            out[i * 2 + 1] = alphabet[v & 15];
        }
        _w(b, out);
    }

    function _finish(Buf memory b) private pure returns (string memory s) {
        bytes memory data = b.data;
        uint256 len = b.len;
        assembly ("memory-safe") {
            mstore(data, len)
        }
        s = string(data);
    }
}
