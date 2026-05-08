// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {ABDKMath64x64 as Math64x64} from "lib/circles-contracts-v2/lib/abdk-libraries-solidity/ABDKMath64x64.sol";

contract GroupDemurrage {
    /// @dev Discounted balance with a last updated timestamp.
    struct DiscountedBalance {
        uint192 balance;
        uint64 lastUpdatedDay;
    }

    // Constants

    /**
     * @notice Demurrage window reduces the resolution for calculating
     * the demurrage of balances from once per second (block.timestamp)
     * to once per day.
     */
    uint256 private constant DEMURRAGE_WINDOW = 1 days;

    /**
     * @dev Maximum value that can be stored or transferred
     */
    uint256 internal constant MAX_VALUE = type(uint192).max;

    /**
     * @dev Reduction factor GAMMA for applying demurrage to balances
     *   demurrage_balance(d) = GAMMA^d * inflationary_balance
     * where 'd' is expressed in days (DEMURRAGE_WINDOW) since demurrage_day_zero,
     * and GAMMA < 1.
     * GAMMA_64x64 stores the numerator for the signed 128bit 64.64
     * fixed decimal point expression:
     *   GAMMA = GAMMA_64x64 / 2**64.
     * To obtain GAMMA for a daily accounting of 7% p.a. demurrage
     *   => GAMMA = (0.93)^(1/365.25)
     *            = 0.99980133200859895743...
     * and expressed in 64.64 fixed point representation:
     *   => GAMMA_64x64 = 18443079296116538654
     * For more details, see ./specifications/TCIP009-demurrage.md
     */
    int128 internal constant GAMMA_64x64 = int128(18443079296116538654);

    /**
     * @notice Inflation day zero stores the start of the global inflation curve
     * As Circles Hub v1 was deployed on Thursday 15th October 2020 at 6:25:30 pm UTC,
     * or 1602786330 unix time, in production this value MUST be set to 1602720000 unix time,
     * or midnight prior of the same day of deployment, marking the start of the first day
     * where there was no inflation on one CRC per hour.
     */
    uint256 internal constant inflationDayZero = 1602720000;

    // Internal functions

    /**
     * @notice Calculate the day since inflation_day_zero for a given timestamp.
     * @param _timestamp Timestamp for which to calculate the day since inflation_day_zero.
     */
    function day(uint256 _timestamp) internal pure returns (uint64) {
        // calculate which day the timestamp is in, rounding down
        // note: max uint64 is 2^64 - 1, so we can safely cast the result
        return uint64((_timestamp - inflationDayZero) / DEMURRAGE_WINDOW);
    }

    /**
     * @dev Calculates the discounted balance given a number of days to discount
     * @param _balance balance to calculate the discounted balance of
     * @param _daysDifference days of difference between the last updated day and the day of interest
     */
    function _calculateDiscountedBalance(uint256 _balance, uint256 _daysDifference) internal pure returns (uint256) {
        if (_daysDifference == 0) {
            return _balance;
        }
        int128 r = _calculateDemurrageFactor(_daysDifference);
        return Math64x64.mulu(r, _balance);
    }

    function _calculateDemurrageFactor(uint256 _dayDifference) internal pure returns (int128) {
        // calculate the value
        return Math64x64.pow(GAMMA_64x64, _dayDifference);
    }
}
