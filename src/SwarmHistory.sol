// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title SwarmHistory
/// @notice Permissionless, append-only, compact commitment of the IMD swarm job history.
/// @dev    The brief allows the swarm history to be "a compact committed summary updated
///         permissionlessly". No on-chain IMD job registry address is given, so this ledger is
///         that summary: anyone may append a job record (one record per unique job id). Every
///         record folds into a rolling entropy hash, per-category counters and a decaying
///         activity "pulse". IMDenza snapshots `entropy`, `jobCount` and `typeProfile()` at mint
///         time (so a piece's composition is frozen forever) and reads `pulse()` live.
///
///         Records are data for the generative system only: nothing here moves funds, so a
///         spammer gains nothing but a different flavour of entropy. There is no owner.
contract SwarmHistory {
    /// @notice Number of job categories (see `JobType`).
    uint256 public constant JOB_TYPE_COUNT = 8;
    /// @notice The first `FOUNDATIONAL_JOBS` recorded jobs leave structural traces in later pieces.
    uint256 public constant FOUNDATIONAL_JOBS = 16;
    /// @notice Pulse scale: 0 (idle) .. PULSE_MAX (saturated).
    uint256 public constant PULSE_MAX = 1_000_000;
    /// @notice Pulse added per recorded job (10% of the scale).
    uint256 public constant PULSE_PER_JOB = 100_000;
    /// @notice Pulse decay per block: a saturated pulse returns to idle in ~7200 blocks (~1 day).
    uint256 public constant PULSE_DECAY_PER_BLOCK = PULSE_MAX / 7200;
    /// @notice Maximum records per batch call.
    uint256 public constant MAX_BATCH = 200;

    /// @notice Job categories. Values above 7 are rejected.
    /// 0 TokenLaunch, 1 Hook, 2 Audit, 3 Website, 4 Image, 5 Contracts, 6 Research, 7 Other
    enum JobType {
        TokenLaunch,
        Hook,
        Audit,
        Website,
        Image,
        Contracts,
        Research,
        Other
    }

    /// @notice Job outcomes. 0 Unknown, 1 Success, 2 Failure, 3 Cancelled.
    enum Outcome {
        Unknown,
        Success,
        Failure,
        Cancelled
    }

    struct JobRecord {
        bytes32 jobId;
        uint8 jobType;
        uint8 outcome;
        uint16 agentCount;
        uint40 jobTimestamp;
        uint40 recordedBlock;
        address recorder;
    }

    error InvalidJobType();
    error InvalidOutcome();
    error InvalidAgentCount();
    error FutureTimestamp();
    error JobAlreadyRecorded(bytes32 jobId);
    error BatchTooLarge();
    error LengthMismatch();
    error IndexOutOfRange();

    event JobRecorded(
        uint256 indexed index,
        bytes32 indexed jobId,
        uint8 jobType,
        uint8 outcome,
        uint16 agentCount,
        uint40 jobTimestamp,
        address recorder,
        bytes32 entropy
    );

    /// @notice Rolling keccak over every record, in order. Starts at zero.
    bytes32 public entropy;
    /// @notice Number of records committed so far.
    uint256 public jobCount;
    /// @notice Sum of agent counts over every record.
    uint256 public totalAgents;
    /// @notice Number of records with outcome Success.
    uint256 public successCount;
    /// @notice Records by category.
    uint256[JOB_TYPE_COUNT] private _typeCounts;
    /// @notice Per-record digest, keccak of all record fields (append-only).
    bytes32[] private _digests;
    /// @notice Per-record packed metadata (append-only).
    JobRecord[] private _records;
    /// @notice Job id -> recorded (prevents duplicates).
    mapping(bytes32 => bool) public isRecorded;

    uint256 private _pulseLevel;
    uint256 private _pulseBlock;

    /// @notice Append one job record.
    /// @param jobId        Unique identifier of the swarm job (e.g. keccak of its id string).
    /// @param jobType      Category, see `JobType`.
    /// @param agentCount   Number of agents that worked the job (1..65535).
    /// @param outcome      Outcome, see `Outcome`.
    /// @param jobTimestamp When the job happened; must not be in the future (back-fill allowed).
    function recordJob(bytes32 jobId, uint8 jobType, uint16 agentCount, uint8 outcome, uint40 jobTimestamp)
        external
        returns (uint256 index)
    {
        index = _record(jobId, jobType, agentCount, outcome, jobTimestamp);
    }

    /// @notice Append several job records in order (used to back-fill history since block 0).
    function recordJobs(
        bytes32[] calldata jobIds,
        uint8[] calldata jobTypes,
        uint16[] calldata agentCounts,
        uint8[] calldata outcomes,
        uint40[] calldata jobTimestamps
    ) external returns (uint256 firstIndex) {
        uint256 n = jobIds.length;
        if (n > MAX_BATCH) revert BatchTooLarge();
        if (jobTypes.length != n || agentCounts.length != n || outcomes.length != n || jobTimestamps.length != n) {
            revert LengthMismatch();
        }
        firstIndex = jobCount;
        for (uint256 i; i < n; ++i) {
            _record(jobIds[i], jobTypes[i], agentCounts[i], outcomes[i], jobTimestamps[i]);
        }
    }

    function _record(bytes32 jobId, uint8 jobType, uint16 agentCount, uint8 outcome, uint40 jobTimestamp)
        private
        returns (uint256 index)
    {
        if (jobType >= JOB_TYPE_COUNT) revert InvalidJobType();
        if (outcome > uint8(Outcome.Cancelled)) revert InvalidOutcome();
        if (agentCount == 0) revert InvalidAgentCount();
        if (jobTimestamp > block.timestamp) revert FutureTimestamp();
        if (isRecorded[jobId]) revert JobAlreadyRecorded(jobId);
        isRecorded[jobId] = true;

        index = jobCount;
        bytes32 digest = keccak256(
            abi.encodePacked(index, jobId, jobType, agentCount, outcome, jobTimestamp, msg.sender, block.number)
        );
        bytes32 newEntropy = keccak256(abi.encodePacked(entropy, digest));
        entropy = newEntropy;
        jobCount = index + 1;
        totalAgents += agentCount;
        if (outcome == uint8(Outcome.Success)) successCount += 1;
        _typeCounts[jobType] += 1;
        _digests.push(digest);
        _records.push(
            JobRecord({
                jobId: jobId,
                jobType: jobType,
                outcome: outcome,
                agentCount: agentCount,
                jobTimestamp: jobTimestamp,
                recordedBlock: uint40(block.number),
                recorder: msg.sender
            })
        );

        // Pulse: decay what is there, then add this job's contribution, capped.
        uint256 level = _currentPulse();
        level += PULSE_PER_JOB;
        if (level > PULSE_MAX) level = PULSE_MAX;
        _pulseLevel = level;
        _pulseBlock = block.number;

        emit JobRecorded(index, jobId, jobType, outcome, agentCount, jobTimestamp, msg.sender, newEntropy);
    }

    function _currentPulse() private view returns (uint256) {
        uint256 elapsed = block.number - _pulseBlock;
        uint256 decay = elapsed * PULSE_DECAY_PER_BLOCK;
        uint256 level = _pulseLevel;
        return decay >= level ? 0 : level - decay;
    }

    /// @notice Live swarm activity level, 0..PULSE_MAX, decaying linearly with blocks since the last record.
    function pulse() external view returns (uint256) {
        return _currentPulse();
    }

    /// @notice Records per category.
    function typeCounts() external view returns (uint256[JOB_TYPE_COUNT] memory counts) {
        counts = _typeCounts;
    }

    /// @notice Compact category profile: byte i (least significant first) = min(255, typeCounts[i]).
    function typeProfile() public view returns (uint64 profile) {
        for (uint256 i; i < JOB_TYPE_COUNT; ++i) {
            uint256 c = _typeCounts[i];
            if (c > 255) c = 255;
            profile |= uint64(c) << uint64(8 * i);
        }
    }

    /// @notice Everything a mint snapshots, in one call.
    function snapshot() external view returns (bytes32 entropy_, uint256 jobCount_, uint64 profile) {
        entropy_ = entropy;
        jobCount_ = jobCount;
        profile = typeProfile();
    }

    /// @notice Digest of record `index`.
    function digestAt(uint256 index) external view returns (bytes32) {
        if (index >= _digests.length) revert IndexOutOfRange();
        return _digests[index];
    }

    /// @notice Full record `index`.
    function recordAt(uint256 index) external view returns (JobRecord memory) {
        if (index >= _records.length) revert IndexOutOfRange();
        return _records[index];
    }

    /// @notice Digests of the foundational jobs (the first `FOUNDATIONAL_JOBS` records), in order,
    ///         limited to those with index < `before`.
    function foundationalDigests(uint256 before) external view returns (bytes32[] memory digests) {
        uint256 n = _digests.length;
        if (n > FOUNDATIONAL_JOBS) n = FOUNDATIONAL_JOBS;
        if (n > before) n = before;
        digests = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            digests[i] = _digests[i];
        }
    }
}
