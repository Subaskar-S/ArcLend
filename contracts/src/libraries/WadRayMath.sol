// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title WadRayMath
 * @author Aave (adapted for production lending protocol)
 * @notice Fixed-point math library for wad (1e18) and ray (1e27) precision.
 * @dev All operations enforce explicit rounding direction.
 *      - "Down" functions round toward zero (default for user-facing amounts).
 *      - "Up" functions round away from zero (used for debt calculations).
 *      No floating point. No unsafe casts. No implicit truncation.
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;

    uint256 internal constant WAD_RAY_RATIO = 1e9;
    uint256 internal constant HALF_WAD_RAY_RATIO = 0.5e9;

    // ============================================================
    //                       WAD OPERATIONS
    // ============================================================

    /**
     * @notice Multiplies two wad values, rounding half down.
     * @param a Wad-scaled value
     * @param b Wad-scaled value
     * @return result = (a * b + HALF_WAD) / WAD
     * @dev Reverts on overflow. Zero-check short-circuit for gas savings.
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        // Overflow check: a * b must not overflow before adding HALF_WAD
        require(a <= (type(uint256).max - HALF_WAD) / b, "WMATH: WAD_MUL_OVERFLOW");

        return (a * b + HALF_WAD) / WAD;
    }

    /**
     * @notice Divides two wad values, rounding half down.
     * @param a Wad-scaled numerator
     * @param b Wad-scaled denominator (must be non-zero)
     * @return result = (a * WAD + b / 2) / b
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: WAD_DIV_BY_ZERO");
        if (a == 0) return 0;

        require(a <= (type(uint256).max - b / 2) / WAD, "WMATH: WAD_DIV_OVERFLOW");

        return (a * WAD + b / 2) / b;
    }

    /**
     * @notice Multiplies two wad values, rounding up.
     * @dev Used for debt calculations where the protocol should not lose precision.
     * @param a Wad-scaled value
     * @param b Wad-scaled value
     * @return result = (a * b + WAD - 1) / WAD
     */
    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - WAD + 1) / b, "WMATH: WAD_MUL_UP_OVERFLOW");
        return (a * b + WAD - 1) / WAD;
    }

    /**
     * @notice Divides two wad values, rounding up.
     * @dev Used for debt calculations.
     * @param a Wad-scaled numerator
     * @param b Wad-scaled denominator
     * @return result = (a * WAD + b - 1) / b
     */
    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: WAD_DIV_UP_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b + 1) / WAD, "WMATH: WAD_DIV_UP_OVERFLOW");
        return (a * WAD + b - 1) / b;
    }

    // ============================================================
    //                       RAY OPERATIONS
    // ============================================================

    /**
     * @notice Multiplies two ray values, rounding half down.
     * @param a Ray-scaled value
     * @param b Ray-scaled value
     * @return result = (a * b + HALF_RAY) / RAY
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - HALF_RAY) / b, "WMATH: RAY_MUL_OVERFLOW");
        return (a * b + HALF_RAY) / RAY;
    }

    /**
     * @notice Divides two ray values, rounding half down.
     * @param a Ray-scaled numerator
     * @param b Ray-scaled denominator
     * @return result = (a * RAY + b / 2) / b
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: RAY_DIV_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b / 2) / RAY, "WMATH: RAY_DIV_OVERFLOW");
        return (a * RAY + b / 2) / b;
    }

    /**
     * @notice Multiplies two ray values, rounding up.
     * @param a Ray-scaled value
     * @param b Ray-scaled value
     * @return result = (a * b + RAY - 1) / RAY
     */
    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - RAY + 1) / b, "WMATH: RAY_MUL_UP_OVERFLOW");
        return (a * b + RAY - 1) / RAY;
    }

    /**
     * @notice Divides two ray values, rounding up.
     * @param a Ray-scaled numerator
     * @param b Ray-scaled denominator
     * @return result = (a * RAY + b - 1) / b
     */
    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: RAY_DIV_UP_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b + 1) / RAY, "WMATH: RAY_DIV_UP_OVERFLOW");
        return (a * RAY + b - 1) / b;
    }

    // ============================================================
    //                       CONVERSIONS
    // ============================================================

    /**
     * @notice Converts ray to wad, rounding down (truncation).
     * @dev This is a lossy conversion — 9 digits of precision are lost.
     * @param a Ray-scaled value
     * @return Wad-scaled value = a / WAD_RAY_RATIO
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = HALF_WAD_RAY_RATIO;
        uint256 result = halfRatio + a;
        require(result >= halfRatio, "WMATH: RAY_TO_WAD_OVERFLOW");
        return result / WAD_RAY_RATIO;
    }

    /**
     * @notice Converts wad to ray (lossless upscale).
     * @param a Wad-scaled value
     * @return Ray-scaled value = a * WAD_RAY_RATIO
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        require(result / WAD_RAY_RATIO == a, "WMATH: WAD_TO_RAY_OVERFLOW");
        return result;
    }
}
