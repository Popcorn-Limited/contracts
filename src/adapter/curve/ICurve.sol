// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IGauge {
    function lp_token() external view returns (address);

    function balanceOf(address _user) external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _rawAmount) external;

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 _index) external view returns (address);
}

interface IGaugeFactory {
    function mint(address _gauge) external;

    function get_gauge_from_lp_token(
        address _lpToken
    ) external view returns (address);
}

interface IGaugeController {
    function gauges(uint256 _gaugeId) external view returns (address);
}

interface IMinter {
    function mint(address _gauge) external;

    function token() external view returns (address);

    function controller() external view returns (address);
}
