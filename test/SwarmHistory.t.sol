// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwarmHistory} from "../src/SwarmHistory.sol";

contract SwarmHistoryTest is Test {
    SwarmHistory swarm;

    function setUp() public {
        vm.roll(100);
        vm.warp(1_700_000_000);
        swarm = new SwarmHistory();
    }

    function test_recordUpdatesEntropyCountersAndPulse() public {
        bytes32 before = swarm.entropy();
        uint256 idx = swarm.recordJob(bytes32("job-1"), 0, 3, 1, uint40(block.timestamp - 10));
        assertEq(idx, 0);
        assertEq(swarm.jobCount(), 1);
        assertTrue(swarm.entropy() != before);
        assertEq(swarm.totalAgents(), 3);
        assertEq(swarm.successCount(), 1);
        assertEq(swarm.typeCounts()[0], 1);
        assertEq(swarm.pulse(), swarm.PULSE_PER_JOB());
        assertTrue(swarm.isRecorded(bytes32("job-1")));
        SwarmHistory.JobRecord memory r = swarm.recordAt(0);
        assertEq(r.jobId, bytes32("job-1"));
        assertEq(r.agentCount, 3);
        assertEq(r.recorder, address(this));
        assertEq(r.recordedBlock, 100);
    }

    function test_duplicateJobIdReverts() public {
        swarm.recordJob(bytes32("dup"), 1, 1, 1, uint40(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(SwarmHistory.JobAlreadyRecorded.selector, bytes32("dup")));
        swarm.recordJob(bytes32("dup"), 2, 2, 2, uint40(block.timestamp));
    }

    function test_invalidInputsRevert() public {
        vm.expectRevert(SwarmHistory.InvalidJobType.selector);
        swarm.recordJob(bytes32("a"), 8, 1, 1, uint40(block.timestamp));
        vm.expectRevert(SwarmHistory.InvalidOutcome.selector);
        swarm.recordJob(bytes32("a"), 0, 1, 4, uint40(block.timestamp));
        vm.expectRevert(SwarmHistory.InvalidAgentCount.selector);
        swarm.recordJob(bytes32("a"), 0, 0, 1, uint40(block.timestamp));
        vm.expectRevert(SwarmHistory.FutureTimestamp.selector);
        swarm.recordJob(bytes32("a"), 0, 1, 1, uint40(block.timestamp + 1));
        assertEq(swarm.jobCount(), 0);
    }

    function test_batchRecordsInOrderAndRejectsMismatch() public {
        bytes32[] memory ids = new bytes32[](3);
        uint8[] memory types = new uint8[](3);
        uint16[] memory agents = new uint16[](3);
        uint8[] memory outcomes = new uint8[](3);
        uint40[] memory ts = new uint40[](3);
        for (uint256 i; i < 3; ++i) {
            ids[i] = bytes32(i + 1);
            types[i] = uint8(i);
            agents[i] = uint16(i + 1);
            outcomes[i] = 1;
            ts[i] = uint40(block.timestamp - i);
        }
        uint256 first = swarm.recordJobs(ids, types, agents, outcomes, ts);
        assertEq(first, 0);
        assertEq(swarm.jobCount(), 3);
        assertEq(swarm.totalAgents(), 6);

        uint8[] memory shortTypes = new uint8[](2);
        vm.expectRevert(SwarmHistory.LengthMismatch.selector);
        swarm.recordJobs(ids, shortTypes, agents, outcomes, ts);

        bytes32[] memory big = new bytes32[](201);
        vm.expectRevert(SwarmHistory.BatchTooLarge.selector);
        swarm.recordJobs(big, new uint8[](201), new uint16[](201), new uint8[](201), new uint40[](201));
    }

    function test_pulseDecaysAndSaturates() public {
        for (uint256 i; i < 12; ++i) {
            swarm.recordJob(bytes32(i + 1), 0, 1, 1, uint40(block.timestamp));
        }
        assertEq(swarm.pulse(), swarm.PULSE_MAX());
        vm.roll(block.number + 3600);
        uint256 half = swarm.PULSE_MAX() - 3600 * swarm.PULSE_DECAY_PER_BLOCK();
        assertEq(swarm.pulse(), half);
        vm.roll(block.number + 10_000);
        assertEq(swarm.pulse(), 0);
        swarm.recordJob(bytes32("later"), 0, 1, 1, uint40(block.timestamp));
        assertEq(swarm.pulse(), swarm.PULSE_PER_JOB());
    }

    function test_typeProfileCapsAt255AndFoundationalDigestsAreLimited() public {
        for (uint256 i; i < 20; ++i) {
            swarm.recordJob(bytes32(i + 1), 2, 1, 1, uint40(block.timestamp));
        }
        uint64 profile = swarm.typeProfile();
        assertEq((profile >> 16) & 0xff, 20);
        assertEq(profile & 0xff, 0);
        assertEq(swarm.foundationalDigests(100).length, 16);
        assertEq(swarm.foundationalDigests(5).length, 5);
        assertEq(swarm.foundationalDigests(0).length, 0);
        assertEq(swarm.foundationalDigests(100)[3], swarm.digestAt(3));
        vm.expectRevert(SwarmHistory.IndexOutOfRange.selector);
        swarm.digestAt(20);
        (bytes32 e, uint256 n, uint64 p) = swarm.snapshot();
        assertEq(e, swarm.entropy());
        assertEq(n, 20);
        assertEq(p, profile);
    }

    function testFuzz_entropyIsOrderSensitive(bytes32 a, bytes32 b) public {
        vm.assume(a != b);
        SwarmHistory other = new SwarmHistory();
        swarm.recordJob(a, 0, 1, 1, 0);
        swarm.recordJob(b, 0, 1, 1, 0);
        other.recordJob(b, 0, 1, 1, 0);
        other.recordJob(a, 0, 1, 1, 0);
        assertTrue(swarm.entropy() != other.entropy());
    }
}
