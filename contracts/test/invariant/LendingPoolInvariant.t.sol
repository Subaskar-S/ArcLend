// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../contracts/libraries/WadRayMath.sol";
import {PercentageMath} from "../../contracts/libraries/PercentageMath.sol";

/**
 * @title MathInvariantTest
 * @notice Invariant tests for the core math libraries used throughout the protocol.
 *
 * Full Diamond integration invariants (total deposits >= total borrows, etc.) are
 * covered by test/integration/FullLifecycle.test.ts (Hardhat).
 * These Foundry invariants target the pure math properties that every financial
 * calculation in the protocol relies on.
 */
contract MathInvariantTest is Test {
    MathHandler internal handler;

    function setUp() public {
        handler = new MathHandler();
        targetContract(address(handler));
    }

    /// @notice wadMul never overflows beyond uint256 when guards pass
    function invariant_WadMul_GuardedInputsNeverOverflow() public view {
        handler.checkWadMulNoOverflow();
    }

    /// @notice percentMul(x, 10000) ≈ x for all valid x
    function invariant_PercentMul_FullBpsIdentity() public view {
        handler.checkPercentMulIdentity();
    }

    /// @notice wadToRay(x) / WAD_RAY_RATIO == x exactly (lossless up-scale)
    function invariant_WadToRay_UpscaleIsExact() public view {
        handler.checkWadToRayExact();
    }

    /// @notice rayToWad(wadToRay(x)) == x  (round-trip is lossless)
    function invariant_WadRay_RoundtripLossless() public view {
        handler.checkWadRayRoundtrip();
    }

    /// @notice wadDiv(a, b) * b ≈ a * WAD  (division inverse of multiplication)
    function invariant_WadDiv_InverseProperty() public view {
        handler.checkWadDivInverse();
    }
}

/**
 * @title MathHandler
 * @notice Stateful handler that exercises math operations and records results
 *         for independent invariant verification.
 *
 * Each invariant has its own independent (lastX, lastResult) pair so that
 * interleaved calls to different actions cannot corrupt each other's state.
 */
contract MathHandler is Test {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    // ── wadMul guard check ────────────────────────────────────────────────────
    uint256 public wadMul_a;
    uint256 public wadMul_b;
    uint256 public wadMul_result;
    bool    public wadMul_hasRecord;

    // ── percentMul identity ───────────────────────────────────────────────────
    uint256 public pct_a;
    uint256 public pct_result;
    bool    public pct_hasRecord;

    // ── wadToRay exact ────────────────────────────────────────────────────────
    uint256 public w2r_a;
    uint256 public w2r_result;
    bool    public w2r_hasRecord;

    // ── round-trip ────────────────────────────────────────────────────────────
    uint256 public rt_a;
    uint256 public rt_result;
    bool    public rt_hasRecord;

    // ── wadDiv inverse ────────────────────────────────────────────────────────
    uint256 public div_a;
    uint256 public div_b;
    uint256 public div_result;
    bool    public div_hasRecord;

    // ─── Actions ─────────────────────────────────────────────────────────────

    function doWadMul(uint96 a, uint96 b) external {
        if (uint256(a) == 0 || uint256(b) == 0) return;
        // Guard: a * b + HALF_WAD must not overflow
        if (uint256(b) > (type(uint256).max - WAD / 2) / uint256(a)) return;

        wadMul_a = uint256(a);
        wadMul_b = uint256(b);
        wadMul_result = uint256(a).wadMul(uint256(b));
        wadMul_hasRecord = true;
    }

    function doPercentMulFull(uint96 a) external {
        // Guard: a * 10000 + 5000 must not overflow
        if (uint256(a) > (type(uint256).max - 5000) / 10000) return;

        pct_a = uint256(a);
        pct_result = uint256(a).percentMul(10000);
        pct_hasRecord = true;
    }

    function doWadToRay(uint96 a) external {
        // Guard: a * WAD_RAY_RATIO must not overflow
        if (uint256(a) > type(uint256).max / WAD_RAY_RATIO) return;

        w2r_a = uint256(a);
        w2r_result = WadRayMath.wadToRay(uint256(a));
        w2r_hasRecord = true;
    }

    function doWadRayRoundtrip(uint96 a) external {
        if (uint256(a) > type(uint256).max / WAD_RAY_RATIO) return;

        uint256 asRay = WadRayMath.wadToRay(uint256(a));
        rt_a = uint256(a);
        rt_result = WadRayMath.rayToWad(asRay);
        rt_hasRecord = true;
    }

    function doWadDiv(uint96 a, uint96 b) external {
        if (uint256(b) == 0) return;
        // Guard: a * WAD + b/2 must not overflow
        if (uint256(a) > (type(uint256).max - uint256(b) / 2) / WAD) return;

        div_a = uint256(a);
        div_b = uint256(b);
        div_result = uint256(a).wadDiv(uint256(b));
        div_hasRecord = true;
    }

    // ─── Invariant checks ────────────────────────────────────────────────────

    /// wadMul result must equal the reference formula
    function checkWadMulNoOverflow() external view {
        if (!wadMul_hasRecord) return;
        uint256 expected = (wadMul_a * wadMul_b + WAD / 2) / WAD;
        assertEq(wadMul_result, expected, "wadMul result != reference formula");
    }

    /// percentMul(a, 10000) must be within ±1 of a
    function checkPercentMulIdentity() external view {
        if (!pct_hasRecord) return;
        assertApproxEqAbs(pct_result, pct_a, 1, "percentMul(a, 10000) should equal a");
    }

    /// wadToRay(a) must equal a * WAD_RAY_RATIO exactly
    function checkWadToRayExact() external view {
        if (!w2r_hasRecord) return;
        assertEq(w2r_result, w2r_a * WAD_RAY_RATIO, "wadToRay result != a * WAD_RAY_RATIO");
    }

    /// rayToWad(wadToRay(a)) must equal a exactly
    function checkWadRayRoundtrip() external view {
        if (!rt_hasRecord) return;
        assertEq(rt_result, rt_a, "wadToRay->rayToWad roundtrip is not lossless");
    }

    /// wadDiv(a, b) must equal the reference formula
    function checkWadDivInverse() external view {
        if (!div_hasRecord) return;
        uint256 expected = (div_a * WAD + div_b / 2) / div_b;
        assertEq(div_result, expected, "wadDiv result != reference formula");
    }
}
