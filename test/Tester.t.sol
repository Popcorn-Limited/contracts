// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

interface IVe {
    function increase_amount(uint256 amount) external;
}

interface IVaultRouter {
    function depositAndStake(address vault, address gauge, uint256 assetAmount, address receiver) external;

    function unstakeAndWithdraw(address vault, address gauge, uint256 burnAmount, address receiver) external;
}

interface IGauge {
    function claim_rewards(address user) external;

    function claimable_reward(address user, address rewardToken) external view returns (uint256);
}

contract Fixer {
    address gauge;
    address rewardToken;

    constructor(address gauge_, address rewardToken_) {
        gauge = gauge_;
        rewardToken = rewardToken_;
    }

    function claim() external {
        uint256 claimableOvcx = IGauge(gauge).claimable_reward(msg.sender, rewardToken);
        IERC20(rewardToken).transfer(gauge, claimableOvcx);
        IGauge(gauge).claim_rewards(msg.sender);
    }
}

contract Tester is Test {
    address router = 0x48943F145686bF5c4580D545CDA405844D1f777b;
    address gauge = 0xc9aD14cefb29506534a973F7E0E97e68eCe4fa3f;
    address assetAddr = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address vaultAddr = 0xD3A17928245064B6DF5095a76e277fe441D538a4;

    IERC20 asset = IERC20(assetAddr);
    IERC4626 vault = IERC4626(vaultAddr);

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }

    function testA() public {
        _testFullWithdraw(0x8864FcD125E24d3cF52AAc71d0EDc61922566740);
        _testFullWithdraw(0x8e130dAB21241dB653BfAD148ADF7887A84c7Ec3);
        _testFullWithdraw(0x0F833bceE52faE0Cf75574d11d327280dF69d21c);
        _testFullWithdraw(0xA5aEf04E03789AD15405D153a82D0b128c36988b);
        _testFullWithdraw(0x1529c4A1682b71FadA517d1BD7Fed68A439F9bdE);

        _testFullWithdraw(0x72566F5A58182A3Dedba2b39508787de819C757f);
        _testFullWithdraw(0x84f40ebac4C7a5216f5f0c64b96a169834058eBC);
        _testFullWithdraw(0x3B62E21a4050E19cD6B65aeC10b8373720D53b90);
        _testFullWithdraw(0xEb4A99A64651247a279C6fe20876D10F9b3D869D);
        _testFullWithdraw(0x18572624dae48120248A50C6e6Aa12E4ed41cf4F);

        _testFullWithdraw(0x3ADB6778474937bCb9C6befC59Cb7952f8cBa05f);
        _testFullWithdraw(0x80C2683506f852b3bf9cb0D6A0948D89e760dE80);
        _testFullWithdraw(0x14198F196897837c62Ce82298Ea1460B05A4f39c);
        _testFullWithdraw(0xB8C59E56CaFB784D63705bFdC4cD7746098C66A2);
        _testFullWithdraw(0xE8C88ed63204452d3663bDa37A3832a227FDb90c);

        _testFullWithdraw(0x1c47963f1A58eB763965e8AC984495a30e8A48ed);
        _testFullWithdraw(0xCe933D37829aDe30c24E77923cE15fF73e029Ec5);
        _testFullWithdraw(0x00847Cfd35A6d0Ce37530d62E5a78D1e333A2068);
        _testFullWithdraw(0xAE889351428ceb16A7517187616FDA9273fF7CD7);
        _testFullWithdraw(0xECf9b65f32653b77439617Bd8a7D6AeB261e5661);

        _testFullWithdraw(0xc0aDAb663C980180E19fa8D4Ad9F504840c6e20D);
        _testFullWithdraw(0xDf6f6E4493246dE78315831BFcAF9fb92d4E4629);
        _testFullWithdraw(0xc0Fa5fD1C9CE8c38d48Df3548b36fdDd21BB66e5);
    }

    function _testFullWithdraw(address user) internal {
        vm.startPrank(user, user);
        uint256 gaugeBal = IERC20(gauge).balanceOf(user);
        IERC20(gauge).approve(router, gaugeBal);
        IVaultRouter(router).unstakeAndWithdraw(vaultAddr, gauge, gaugeBal, user);
        vm.stopPrank();
    }

    function testB() public {
        Fixer fixer = new Fixer(
            gauge,
            0x59a696bF34Eae5AD8Fd472020e3Bed410694a230
        );

        vm.prank(0x22f5413C075Ccd56D575A54763831C4c27A37Bdb);
        IERC20(0x59a696bF34Eae5AD8Fd472020e3Bed410694a230).transfer(address(fixer), 100e18);

        vm.prank(0x22f5413C075Ccd56D575A54763831C4c27A37Bdb);
        fixer.claim();
    }
}
