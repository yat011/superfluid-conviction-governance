pragma solidity 0.7.6;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

library mathUtils {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    uint256 public constant TWO_128 = 0x100000000000000000000000000000000; // 2^128
    uint256 public constant TWO_127 = 0x80000000000000000000000000000000; // 2^127

    function convertToFixedPoint128(
        uint256 input,
        uint256 origDecimalMultiplier
    ) public view returns (uint256) {
        return (input << 128).div(origDecimalMultiplier);
    }

    function convertFixedPoint128To(
        uint256 input,
        uint256 origDecimalMultiplier
    ) public view returns (uint256) {
        return input.mul(origDecimalMultiplier) >> 128;
    }

    function convertSignedFixedPoint128To(
        int256 input,
        uint256 origDecimalMultiplier
    ) public view returns (int256) {
        if (input >= 0) {
            return int256(uint256(input).mul(origDecimalMultiplier) >> 128);
        } else {
            return -int256((uint256(-input).mul(origDecimalMultiplier) >> 128));
        }
    }

    // /**
    //  * ref: https://github.com/1Hive/conviction-voting-app/blob/master/contracts/ConvictionVoting.sol
    //  * Multiply _a by _b / 2^128.  Parameter _a should be less than or equal to
    //  * 2^128 and parameter _b should be less than 2^128.
    //  * @param _a left argument
    //  * @param _b right argument
    //  * @return _a * _b / 2^128
    //  */
    function fixedFractionalMul(uint256 _a, uint256 _b)
        internal
        pure
        returns (uint256 _result)
    {
        require(_a <= TWO_128, "_a should be less than or equal to 2^128");
        require(_b < TWO_128, "_b should be less than 2^128");
        return _a.mul(_b).add(TWO_127) >> 128;
    }

    // /**
    //  * Calculate (_a / 2^128)^_b * 2^128.  Parameter _a should be less than 2^128.
    //  *
    //  * @param _a left argument
    //  * @param _b right argument
    //  * @return (_a / 2^128)^_b * 2^128
    //  */
    function fixedFractionalPow(uint256 _a, uint256 _b)
        internal
        pure
        returns (uint256 _result)
    {
        require(_a < TWO_128, "_a should be less than 2^128");
        uint256 a = _a;
        uint256 b = _b;
        _result = TWO_128;
        while (b > 0) {
            if (b & 1 == 0) {
                a = fixedFractionalMul(a, a);
                b >>= 1;
            } else {
                _result = fixedFractionalMul(_result, a);
                b -= 1;
            }
        }
    }

    uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;

    uint128 private constant TWO127 = 0x80000000000000000000000000000000;

    // /**
    //  * Return index of most significant non-zero bit in given non-zero 256-bit
    //  * unsigned integer value.
    //  *
    //  * @param x value to get index of most significant non-zero bit in
    //  * @return index of most significant non-zero bit in given number
    //  */
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        if (x >= 0x100000000000000000000000000000000) {
            x >>= 128;
            r += 128;
        }
        if (x >= 0x10000000000000000) {
            x >>= 64;
            r += 64;
        }
        if (x >= 0x100000000) {
            x >>= 32;
            r += 32;
        }
        if (x >= 0x10000) {
            x >>= 16;
            r += 16;
        }
        if (x >= 0x100) {
            x >>= 8;
            r += 8;
        }
        if (x >= 0x10) {
            x >>= 4;
            r += 4;
        }
        if (x >= 0x4) {
            x >>= 2;
            r += 2;
        }
        if (x >= 0x2) r += 1; // No need to shift x anymore
    }

    // /**
    //  * Calculate log_2 (x / 2^128) * 2^128.
    //  *
    //  * @param x parameter value
    //  * @return log_2 (x / 2^128) * 2^128
    //  */
    function log_2(uint256 x) internal pure returns (int256) {
        require(x > 0);

        uint8 msb = mostSignificantBit(x);

        if (msb > 128) x >>= msb - 128;
        else if (msb < 128) x <<= 128 - msb;

        x &= TWO128_1;

        int256 result = (int256(msb) - 128) << 128; // Integer part of log_2

        int256 bit = TWO127;
        for (uint8 i = 0; i < 128 && x > 0; i++) {
            x = (x << 1) + ((x * x + TWO127) >> 128);
            if (x > TWO128_1) {
                result |= bit;
                x = (x >> 1) - TWO127;
            }
            bit >>= 1;
        }

        return result;
    }

    // /**
    //  * Calculate ln (x / 2^128) * 2^128.
    //  *
    //  * @param x parameter value
    //  * @return ln (x / 2^128) * 2^128
    //  */
    function ln(uint256 x) internal pure returns (int256) {
        require(x > 0);

        int256 l2 = log_2(x);
        if (l2 == 0) return 0;
        else {
            uint256 al2 = uint256(l2 > 0 ? l2 : -l2);
            uint8 msb = mostSignificantBit(al2);
            if (msb > 127) al2 >>= msb - 127;
            al2 = (al2 * LN2 + TWO127) >> 128;
            if (msb > 127) al2 <<= msb - 127;

            return int256(l2 >= 0 ? al2 : -al2);
        }
    }
}
