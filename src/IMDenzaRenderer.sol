// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMDenzaField} from "./IMDenzaField.sol";
import {SwarmHistory} from "./SwarmHistory.sol";

/// @title IMDenzaRenderer
/// @notice Turns a token's immutable mint data plus the swarm history into traits, an animated
///         SVG and an ERC-721 metadata data-URI. Fully on-chain; no owner; no mutable state.
/// @dev    Composition seed = keccak(tokenHash, swarmEntropyAtMint, tokenId). The token id is part
///         of the preimage, so two distinct tokens can never share a composition seed (a keccak
///         collision would be required), and IMDenza additionally refuses a reused token hash.
///         Everything derived from the seed and the mint snapshot is frozen forever. Only the
///         "pulse" (recent swarm activity) is read live and only drives animation speed,
///         breathing amplitude and saturation, never the composition.
contract IMDenzaRenderer {
    using Strings for uint256;

    struct Piece {
        uint256 tokenId;
        bytes32 tokenHash; // from the mint transaction context
        bytes32 swarmEntropy; // SwarmHistory.entropy at mint
        uint256 swarmJobIndex; // SwarmHistory.jobCount at mint
        uint64 typeProfile; // SwarmHistory.typeProfile() at mint
    }

    struct Traits {
        bytes32 seed;
        uint8 scale; // 0 Small, 1 Medium, 2 Large, 3 Jumbo
        uint8 turbulence; // 0 None, 1 Low, 2 Mid, 3 High
        uint8 density; // 0 Sparse, 1 Medium, 2 Dense
        uint8 palette; // 0..7
        uint8 collision; // 0 Tight, 1 Standard, 2 Airy
        bool outline;
        uint16 baseAngle; // brads
        uint8 accents; // accent marks drawn
        uint8 traces; // foundational traces drawn
        uint256 jobsFrom; // contributing job range start (always 0)
        uint256 jobsTo; // contributing job range end (exclusive)
        uint256 pulse; // live, 0..PULSE_MAX
        uint8 pulseInfluence; // 0..100
    }

    /// @notice 8 palettes x (7 stroke colours + outline colour + background) x 3 bytes.
    bytes private constant PALETTES = hex"d94f2bf2a5411f1a17f6d8ae7b2d26e8c1702e4057" hex"2a1a12f4e8d6"
        hex"16425b3a7ca581c3d7d9dcd62f6690f4a2611b1b1e" hex"0e1f2ce9eef2"
        hex"3a5a40588157a3b18adad7cd344e41e9c46abc6c25" hex"1f2e22f1f3e0"
        hex"f5f5f59a9a9a444444e639462b2b2bd4d4d46c757d" hex"000000121212"
        hex"2b2b2bd8c3a58e8d8ae85a4fe98074eae7dc3d405b" hex"1c1c1cfbf7f0"
        hex"ff6b6bffd93d6bcb774d96fff473b9845ec22c2c54" hex"3a2a4afff0f6"
        hex"c2653ae3a27a8a3b1cf0c9a85b3a29d9a0662e2a27" hex"2a1a10f3e1d2"
        hex"0b3954087e8bbfd7eaff5a5fc81d251c5d99e0f2f1" hex"071f2eeef6fb";

    /// @notice Accent colours per job category (see SwarmHistory.JobType), 3 bytes each.
    bytes private constant ACCENTS = hex"ffb703fb8500e63946219ebc8338ec3a86ff06d6a0ffd166";

    SwarmHistory public immutable swarm;
    IMDenzaField public immutable field;

    constructor(address swarm_, address field_) {
        require(swarm_ != address(0) && field_ != address(0), "zero address");
        swarm = SwarmHistory(swarm_);
        field = IMDenzaField(field_);
    }

    // ---------------------------------------------------------------- traits

    /// @notice Composition seed of a piece.
    function seedOf(Piece memory p) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(p.tokenHash, p.swarmEntropy, p.tokenId));
    }

    /// @notice Readable traits of a piece. Everything except `pulse`/`pulseInfluence` is frozen.
    function traits(Piece memory p) public view returns (Traits memory t) {
        bytes32 s = seedOf(p);
        bytes32 e = p.swarmEntropy;
        t.seed = s;
        t.scale = _bucket(_biased(s, e, 0), 35, 70, 92);
        t.turbulence = _bucket(_biased(s, e, 1), 20, 55, 85);
        // Density has three buckets: the top threshold (110 + 10) is above `_biased`'s maximum (119).
        t.density = _bucket(_biased(s, e, 2), 30, 75, 110);
        uint256 favoured = uint8(e[3]) % 8;
        t.palette = uint8(uint8(s[3]) % 100 < 25 ? favoured : uint8(s[4]) % 8);
        t.outline = uint8(s[5]) % 100 < 35;
        t.baseAngle = uint16((uint256(uint8(s[6])) << 2) | (uint8(s[7]) & 3));
        t.collision = uint8(s[8]) % 3;
        t.jobsFrom = 0;
        t.jobsTo = p.swarmJobIndex;
        uint256 pulse = swarm.pulse();
        t.pulse = pulse;
        t.pulseInfluence = uint8(pulse * 100 / swarm.PULSE_MAX());
        t.accents = _accentCount(p.typeProfile);
        uint256 tr = p.swarmJobIndex;
        uint256 f = swarm.FOUNDATIONAL_JOBS();
        if (tr > f) tr = f;
        t.traces = uint8(tr);
    }

    function _biased(bytes32 s, bytes32 e, uint256 i) private pure returns (uint256) {
        // seed byte 0..99, pushed by up to +-10 by the swarm entropy byte at the same index (0..119
        // after the +10 offset)
        uint256 v = uint8(s[i]) % 100 + 10;
        return v + uint8(e[i]) % 21 - 10;
    }

    function _bucket(uint256 v, uint256 a, uint256 b, uint256 c) private pure returns (uint8) {
        if (v < a + 10) return 0;
        if (v < b + 10) return 1;
        if (v < c + 10) return 2;
        return 3;
    }

    function _accentCount(uint64 profile) private pure returns (uint8 n) {
        for (uint256 i; i < 8; ++i) {
            uint256 c = (profile >> (8 * i)) & 0xff;
            if (c > 0) n += c >= 32 ? 2 : 1;
        }
    }

    // ---------------------------------------------------------------- field params

    function _params(Traits memory t) private pure returns (IMDenzaField.Params memory q) {
        q.seed = t.seed;
        q.baseAngle = t.baseAngle;
        q.outline = t.outline;
        if (t.scale == 0) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (4, 14, 10, 40, 80);
        else if (t.scale == 1) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (12, 34, 14, 36, 110);
        else if (t.scale == 2) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (30, 70, 18, 32, 150);
        else (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (60, 130, 24, 28, 200);
        q.turb = [40, 150, 330, 720][t.turbulence];
        q.attempts = [45, 80, 120][t.density];
        q.gap = [0, 4, 10][t.collision];
        uint256 pulse = t.pulse;
        uint256 max = 1_000_000;
        q.thickVar = uint16(6 + pulse * 14 / max);
        q.speed = uint16(100 + pulse * 100 / max);
        q.flowAmp = uint16(20 + pulse * 40 / max);
    }

    // ---------------------------------------------------------------- svg

    /// @notice Raw animated SVG of a piece.
    function svg(Piece memory p) public view returns (string memory) {
        Traits memory t = traits(p);
        (string memory defs, string memory uses,) = field.render(_params(t), _palette(t.palette));
        return string.concat(_head(t), _traces(p, t), "<defs>", defs, "</defs>", uses, _accents(p, t), "</g></svg>");
    }

    function _palette(uint256 i) private pure returns (bytes memory out) {
        out = new bytes(24);
        for (uint256 k; k < 24; ++k) {
            out[k] = PALETTES[i * 27 + k];
        }
    }

    function _hex(bytes memory src, uint256 offset) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(6);
        for (uint256 i; i < 3; ++i) {
            uint8 v = uint8(src[offset + i]);
            out[i * 2] = alphabet[v >> 4];
            out[i * 2 + 1] = alphabet[v & 15];
        }
        return string(out);
    }

    function _head(Traits memory t) private pure returns (string memory) {
        uint256 pulse = t.pulse;
        uint256 hue = 4 + pulse * 12 / 1_000_000; // degrees
        uint256 sat = 100 + pulse * 50 / 1_000_000; // percent
        uint256 hueDur = 24000 * 100 / (100 + pulse * 100 / 1_000_000); // ms
        string memory bg = _hex(PALETTES, t.palette * 27 + 24);
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000"><style>',
            ".s,.o{fill:none;stroke-linecap:butt;stroke-linejoin:round;stroke-width:var(--w);",
            "animation:f var(--t) ease-in-out var(--d) infinite alternate,b calc(var(--t)*1.37) ease-in-out var(--d) infinite alternate}",
            ".k{animation:f var(--t) ease-in-out var(--d) infinite alternate,b calc(var(--t)*1.37) ease-in-out var(--d) infinite alternate,",
            "k calc(var(--t)*2.3) ease-in-out var(--d) infinite alternate}",
            ".m{transform-box:fill-box;transform-origin:center;animation:m 5s ease-in-out infinite alternate}",
            "#g{animation:h ",
            _sec(hueDur),
            " ease-in-out infinite alternate}",
            "@keyframes f{to{transform:translate(var(--x),var(--y))}}@keyframes b{to{stroke-width:var(--w2)}}",
            "@keyframes k{to{opacity:.3}}@keyframes m{to{transform:scale(1.35)}}@keyframes h{to{filter:hue-rotate(",
            hue.toString(),
            "deg) saturate(",
            _pct(sat),
            ")}}</style><rect width=\"1000\" height=\"1000\" fill=\"#",
            bg,
            '"/><g id="g">'
        );
    }

    /// @dev Foundational jobs leave faint structural lines through the piece.
    function _traces(Piece memory p, Traits memory t) private view returns (string memory out) {
        bytes32[] memory digests = swarm.foundationalDigests(p.swarmJobIndex);
        if (digests.length == 0) return "";
        out = string.concat('<g opacity=".11" stroke="#', _hex(PALETTES, t.palette * 27 + 21), '" stroke-width="2">');
        for (uint256 i; i < digests.length; ++i) {
            bytes32 d = digests[i];
            int256 cx = int256(uint256(uint8(d[0])) * 1000 / 255);
            int256 cy = int256(uint256(uint8(d[1])) * 1000 / 255);
            uint256 a = (uint256(uint8(d[2])) << 2) | (uint8(d[3]) & 3);
            int256 dx = _sin(a + 256) * 800 / 1000;
            int256 dy = _sin(a) * 800 / 1000;
            out = string.concat(
                out,
                '<line x1="',
                _int(cx - dx),
                '" y1="',
                _int(cy - dy),
                '" x2="',
                _int(cx + dx),
                '" y2="',
                _int(cy + dy),
                '"/>'
            );
        }
        out = string.concat(out, "</g>");
    }

    /// @dev Job categories present at mint add small geometric marks in accent colours.
    function _accents(Piece memory p, Traits memory t) private pure returns (string memory out) {
        if (t.accents == 0) return "";
        out = '<g class="a" opacity=".85">';
        bytes32 s = t.seed;
        uint256 k;
        for (uint256 i; i < 8; ++i) {
            uint256 c = (p.typeProfile >> (8 * i)) & 0xff;
            if (c == 0) continue;
            uint256 marks = c >= 32 ? 2 : 1;
            for (uint256 m; m < marks; ++m) {
                uint256 x = 60 + uint256(uint8(s[(10 + k * 2) % 32])) * 880 / 255;
                uint256 y = 60 + uint256(uint8(s[(11 + k * 2) % 32])) * 880 / 255;
                uint256 size = 8 + (c > 256 ? 16 : c / 16);
                out = string.concat(out, _mark(i, x, y, size, _hex(ACCENTS, i * 3)));
                ++k;
            }
        }
        out = string.concat(out, "</g>");
    }

    function _mark(uint256 kind, uint256 x, uint256 y, uint256 r, string memory colour)
        private
        pure
        returns (string memory)
    {
        string memory xs = x.toString();
        string memory ys = y.toString();
        string memory rs = r.toString();
        if (kind == 0) {
            return string.concat('<circle class="m" cx="', xs, '" cy="', ys, '" r="', rs, '" fill="#', colour, '"/>');
        }
        if (kind == 1) {
            return string.concat(
                '<circle class="m" cx="',
                xs,
                '" cy="',
                ys,
                '" r="',
                rs,
                '" fill="none" stroke-width="3" stroke="#',
                colour,
                '"/>'
            );
        }
        if (kind == 2 || kind == 3) {
            uint256 w = kind == 2 ? r : r * 2;
            return string.concat(
                '<rect class="m" x="',
                (x - r / 2).toString(),
                '" y="',
                (y - r / 2).toString(),
                '" width="',
                w.toString(),
                '" height="',
                rs,
                '" fill="#',
                colour,
                '"/>'
            );
        }
        if (kind == 4 || kind == 5) {
            // triangle (4) or diamond (5)
            string memory pts = kind == 4
                ? string.concat(
                    xs,
                    ",",
                    (y - r).toString(),
                    " ",
                    (x + r).toString(),
                    ",",
                    (y + r).toString(),
                    " ",
                    (x - r).toString(),
                    ",",
                    (y + r).toString()
                )
                : string.concat(
                    xs,
                    ",",
                    (y - r).toString(),
                    " ",
                    (x + r).toString(),
                    ",",
                    ys,
                    " ",
                    xs,
                    ",",
                    (y + r).toString(),
                    " ",
                    (x - r).toString(),
                    ",",
                    ys
                );
            return string.concat('<polygon class="m" points="', pts, '" fill="#', colour, '"/>');
        }
        if (kind == 6) {
            return string.concat(
                '<path class="m" d="M',
                (x - r).toString(),
                " ",
                ys,
                "H",
                (x + r).toString(),
                "M",
                xs,
                " ",
                (y - r).toString(),
                "V",
                (y + r).toString(),
                '" stroke-width="3" stroke="#',
                colour,
                '"/>'
            );
        }
        return string.concat(
            '<circle class="m" cx="', xs, '" cy="', ys, '" r="', (r / 2 + 2).toString(), '" fill="#', colour, '"/>'
        );
    }

    // ---------------------------------------------------------------- metadata

    /// @notice ERC-721 metadata as a base64 JSON data URI with an embedded base64 SVG image.
    function tokenURI(Piece memory p) external view returns (string memory) {
        Traits memory t = traits(p);
        (string memory defs, string memory uses, uint256 count) = field.render(_params(t), _palette(t.palette));
        string memory image =
            string.concat(_head(t), _traces(p, t), "<defs>", defs, "</defs>", uses, _accents(p, t), "</g></svg>");
        string memory json = string.concat(
            '{"name":"IMDenza #',
            p.tokenId.toString(),
            '","description":"IMDenza: fully on-chain animated flow fields seeded by the mint transaction and modulated by the complete history of IMD swarm jobs.",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '","attributes":[',
            _attributes(p, t, count),
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _attributes(Piece memory p, Traits memory t, uint256 count) private pure returns (string memory) {
        string[4] memory scales = ["Small", "Medium", "Large", "Jumbo"];
        string[4] memory turbs = ["None", "Low", "Mid", "High"];
        string[3] memory dens = ["Sparse", "Medium", "Dense"];
        string[8] memory pals = ["Ember", "Harbor", "Meadow", "Noir", "Linen", "Candy", "Terracotta", "Glacier"];
        string[3] memory cols = ["Tight", "Standard", "Airy"];
        string memory a = string.concat(
            _attr("Scale", scales[t.scale]),
            _attr("Turbulence", turbs[t.turbulence]),
            _attr("Density", dens[t.density]),
            _attr("Palette", pals[t.palette]),
            _attr("Collision", cols[t.collision]),
            _attr("Outline", t.outline ? "Yes" : "No")
        );
        string memory b = string.concat(
            _num("Shapes", count),
            _num("Pulse Influence", t.pulseInfluence),
            _num("Accent Marks", t.accents),
            _num("Foundational Traces", t.traces),
            _num("Swarm Jobs At Mint", t.jobsTo),
            _attr("Contributing Job Range", t.jobsTo == 0 ? "none" : string.concat("0-", (t.jobsTo - 1).toString())),
            _attr("Token Hash", uint256(p.tokenHash).toHexString(32)),
            _attr("Swarm Entropy", uint256(p.swarmEntropy).toHexString(32))
        );
        return string.concat(a, b);
    }

    function _attr(string memory k, string memory v) private pure returns (string memory) {
        return string.concat('{"trait_type":"', k, '","value":"', v, '"},');
    }

    function _num(string memory k, uint256 v) private pure returns (string memory) {
        return string.concat('{"trait_type":"', k, '","value":', v.toString(), "},");
    }

    // ---------------------------------------------------------------- helpers

    function _sin(uint256 a) private pure returns (int256) {
        a &= 1023;
        bool neg = a >= 512;
        uint256 x = neg ? a - 512 : a;
        uint256 q = x * (512 - x);
        int256 s = int256((16000 * q) / (1310720 - 4 * q));
        return neg ? -s : s;
    }

    function _int(int256 v) private pure returns (string memory) {
        return v < 0 ? string.concat("-", uint256(-v).toString()) : uint256(v).toString();
    }

    function _sec(uint256 ms) private pure returns (string memory) {
        return string.concat((ms / 1000).toString(), ".", ((ms % 1000) / 100).toString(), "s");
    }

    function _pct(uint256 percent) private pure returns (string memory) {
        return
            string.concat((percent / 100).toString(), ".", (percent % 100 / 10).toString(), (percent % 10).toString());
    }
}
