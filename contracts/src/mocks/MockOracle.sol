// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockOracle
 * @notice Price oracle mock for AURA Protocol.
 * @dev Returns collateral price in debt asset terms (scaled to 1e18).
 */
contract MockOracle {
    uint256 private _price;

    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    constructor(uint256 initialPrice) {
        _price = initialPrice;
    }

    /**
     * @notice Get current price of collateral in debt token (1e18).
     */
    function getPrice() external view returns (uint256) {
        return _price;
    }

    /**
     * @notice Set current price of collateral.
     */
    function setPrice(uint256 newPrice) external {
        uint256 oldPrice = _price;
        _price = newPrice;
        emit PriceUpdated(oldPrice, newPrice);
    }
}
