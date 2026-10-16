// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {IMDenzaField} from "../src/IMDenzaField.sol";
import {IMDenzaRenderer} from "../src/IMDenzaRenderer.sol";

contract IMDenzaRendererTest is BaseTest {
    function _piece(uint256 id, bytes32 hash) internal view returns (IMDenzaRenderer.Piece memory p) {
        p = IMDenzaRenderer.Piece({
            tokenId: id,
            tokenHash: hash,
            swarmEntropy: swarm.entropy(),
            swarmJobIndex: swarm.jobCount(),
            typeProfile: swarm.typeProfile()
        });
    }

    function test_rendererRejectsZeroAddresses() public {
        vm.expectRevert("zero address");
        new IMDenzaRenderer(address(0), address(field));
        vm.expectRevert("zero address");
        new IMDenzaRenderer(address(swarm), address(0));
    }

    function test_deterministicForSamePiece() public view {
        IMDenzaRenderer.Piece memory p = _piece(1, keccak256("h"));
        assertEq(renderer.svg(p), renderer.svg(p));
        assertEq(renderer.tokenURI(p), renderer.tokenURI(p));
    }

    function test_tokenIdAloneChangesTheComposition() public view {
        bytes32 h = keccak256("same hash");
        IMDenzaRenderer.Piece memory a = _piece(1, h);
        IMDenzaRenderer.Piece memory b = _piece(2, h);
        assertTrue(renderer.seedOf(a) != renderer.seedOf(b));
        assertTrue(keccak256(bytes(renderer.svg(a))) != keccak256(bytes(renderer.svg(b))));
    }

    function test_pulseChangesAnimationOnlyNotComposition() public {
        IMDenzaRenderer.Piece memory p = _piece(1, keccak256("h"));
        IMDenzaRenderer.Traits memory t0 = renderer.traits(p);
        string memory s0 = renderer.svg(p);
        assertEq(t0.pulse, 0);

        // Recent swarm activity: pulse rises, composition traits stay frozen.
        swarm.recordJob(bytes32("j"), 4, 3, 1, uint40(block.timestamp));
        IMDenzaRenderer.Traits memory t1 = renderer.traits(p);
        assertEq(t1.pulse, swarm.PULSE_PER_JOB());
        assertEq(t1.seed, t0.seed);
        assertEq(t1.scale, t0.scale);
        assertEq(t1.turbulence, t0.turbulence);
        assertEq(t1.density, t0.density);
        assertEq(t1.palette, t0.palette);
        assertEq(t1.outline, t0.outline);
        assertEq(t1.baseAngle, t0.baseAngle);
        assertTrue(keccak256(bytes(renderer.svg(p))) != keccak256(bytes(s0)));

        // The piece snapshot (jobIndex/profile) did not change, so no new accents or traces.
        assertEq(t1.accents, t0.accents);
        assertEq(t1.traces, t0.traces);

        // Once the pulse has fully decayed the exact original bytes come back.
        vm.roll(block.number + 20_000);
        assertEq(renderer.svg(p), s0);
    }

    function test_swarmHistoryModulatesLaterPieces() public {
        bytes32 h = keccak256("h");
        IMDenzaRenderer.Piece memory early = _piece(1, h);
        for (uint256 i; i < 40; ++i) {
            swarm.recordJob(bytes32(i + 1), uint8(i % 8), 2, 1, uint40(block.timestamp));
        }
        vm.roll(block.number + 20_000); // let the pulse decay so only the snapshot differs
        IMDenzaRenderer.Piece memory late = _piece(1, h);
        assertTrue(renderer.seedOf(early) != renderer.seedOf(late));
        IMDenzaRenderer.Traits memory te = renderer.traits(early);
        IMDenzaRenderer.Traits memory tl = renderer.traits(late);
        assertEq(te.traces, 0);
        assertEq(tl.traces, 16);
        assertEq(te.accents, 0);
        assertEq(tl.accents, 8); // 40 jobs over 8 categories: one mark per category
        assertEq(tl.jobsTo, 40);
    }

    function testFuzz_fieldRendersForAnySeed(bytes32 seed, uint8 scale) public view {
        scale = uint8(bound(scale, 0, 3));
        IMDenzaField.Params memory q;
        q.seed = seed;
        q.attempts = 30;
        q.baseAngle = uint16(uint256(seed) & 1023);
        q.turb = 330;
        q.gap = 4;
        q.thickVar = 8;
        q.speed = 100;
        q.flowAmp = 30;
        q.outline = scale % 2 == 0;
        if (scale == 0) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (4, 14, 10, 40, 80);
        else if (scale == 1) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (12, 34, 14, 36, 110);
        else if (scale == 2) (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (30, 70, 18, 32, 150);
        else (q.minThick, q.maxThick, q.stepLen, q.maxSteps, q.noiseCell) = (60, 130, 24, 28, 200);
        bytes memory pal = hex"d94f2bf2a5411f1a17f6d8ae7b2d26e8c1702e40572a1a12";
        (string memory defs, string memory uses, uint256 count) = field.render(q, pal);
        assertGt(count, 0);
        assertGt(bytes(defs).length, 0);
        assertGt(bytes(uses).length, 0);
    }

    function test_fieldRejectsBadInputs() public {
        IMDenzaField.Params memory q;
        q.noiseCell = 80;
        q.stepLen = 10;
        q.maxSteps = 10;
        q.maxThick = 10;
        vm.expectRevert("palette");
        field.render(q, hex"00");
        q.noiseCell = 10;
        vm.expectRevert("params");
        field.render(q, new bytes(24));
    }

    function testFuzz_everyTokenRenders(uint256 tokenId, bytes32 hash) public view {
        tokenId = bound(tokenId, 1, 3333);
        IMDenzaRenderer.Piece memory p = _piece(tokenId, hash);
        IMDenzaRenderer.Traits memory t = renderer.traits(p);
        assertTrue(t.scale <= 3 && t.turbulence <= 3 && t.density <= 2 && t.palette <= 7 && t.collision <= 2);
        string memory s = renderer.svg(p);
        assertGt(bytes(s).length, 1000);
    }
}
