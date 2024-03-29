// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";

contract SetPermission is Script {
    address deployer;

    VaultController controller =
        VaultController(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

    address[] targets;
    Permission[] permissions;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        targets = [
            0x865500c065287B6727d31ddD9BAc8e959bBB809F,
            0x6282FCa35943faBE45d6056F3751b3cf2Bf4504E,
            0x2Af5feB31803BF806b6516EED4b10aC6767cb125,
            0xD1BeaD7CadcCC6b6a715A6272c39F1EC54F6EC99,
            0x31C0dac4c896cb84adFEF2F8e41cb9295EEc93c2,
            0xfE5716D0C141F3d800995420e1d3fB0D0CFFCC31,
            0xBE2bD093B8F342e060E79Fad6059B1057F016Ba4,
            0x9f8e3E829DbF75dc035d79502bae87d412c2bC36,
            0x56d50Ca676f9AdC1E90f29F25e0d12DeC02746eE,
            0xFc6a9D39b44a174B5Ba708dBaa437632d78B8585,
            0x03D0F88aDc096259b49079073aED693Ba5f425EE,
            0x8cB4f56e9bAa398b6F6a6Fb1B2C4E8ca8cda6ae5,
            0xa40DEAA277422bFa8F31297f1a394000DA253c51,
            0x34892e2AcAb7Db584DE000fAa1Ca142040176b26,
            0x83BE6565c0758f746c09f95559B45Cfb9a0FFFc4,
            0xCc19786F91BB1F3F3Fd9A2eA9fD9a54F7743039E,
            0x5Bcd31a28D77a1A5Ef5e0146Ab91e6f43D7100b7,
            0xe703ccDE82b2B40AdBdD9E5C674e521468159177,
            0xD6F5BEF9b63bf648EeA43b80B480BE653138D116,
            0xa6b53563a13de4C443FC4fd60d7127Ad54924cd3,
            0x6e8Aa36716669C575ab308c0F48965A681Db03B4,
            0x4dE81AD42E9651755716177fAe9911c54F5b055B,
            0x9d7b626cb1c07f63A46a8337111b65D6Cb4B8a58,
            0xd9800EeF1756f156E025859eE0DBE6E5f6a6428b,
            0x047c41817954b51309a2bd6f60e47bC115C23f1F,
            0x3f80F7aE80F54DDB31B1211e7d03CF24fCBB8334,
            0x445BE44783b9B04B27d23b87eD69985aBAb1BeF3,
            0x8785e892e6C7f1BcE907680cE35B580EEA7Fb24c,
            0x0d2846d81099CE35cFB3CF5A81394E7d2f078f37,
            0x7eAeA98668f1C062266B4C186F57eAfb6dF6Fbe4,
            0xaa43DFb8fC642Feb9887cDFFff1DAAd1cFA511B4,
            0xdE5a3596750e22891352c62f68C86D4cF30256e9,
            0x49b562bDcd28dB124f6bA51DEB8Ca483563c067a,
            0xE0686bBfeCE4861a731A8445E83826090441F1fc,
            0x8affC4591DE6eAEc6836c243b00b80F4339f99f5,
            0x4115150523599D1F6C6Fa27F5A4C27D578Fd8ce5,
            0x6660fd0a97Af41c6A7b29450D3532FeDdBe0478A,
            0xAf59cca8d658fe89e83d78D1d39125E3F4b2a529,
            0xB9911AB699FD781efDA446e7FD995d375B437c8B,
            0xcAa51337D91d61E0575f3892Cfc6B243a335C0f4,
            0xeb5A443d4b4deF6f81C0Ef0B66Af5168a34A7f38,
            0xDe9aEC2f40c7Bc783974122Ef84c7f1F237F46Dd,
            0x842B8091dD92A1BB590527B95B9a2915C73BA491,
            0x941E1dEAc6c58391b266AB849cB7368d6a60910E,
            0x61F96CA5c79c9753C93244c73f1d4b4a90c1aC8c,
            0xE010B164E54735Bb6401c426E9b4Dc16949c00B8,
            0x4742c355711a2790b17CC0Fe48035a1AF9C22432,
            0x6853691Ca8Da03Da16194E468068bE5A80F103b0,
            0x15780E0e9618c26dA679740C43bEc76830Ff187b,
            0x572181c7B073966F9FA037Cf1F79a647f5AA9Eb7,
            0xb9548238d875fB4e12727B2750D8a0bDbc7171c7,
            0x8448758c3Cad93675eACe770847aA9507f8bDe0B,
            0x245186CaA063b13d0025891c0d513aCf552fB38E,
            0x4a37227BFE2aD5c5126E176e16363d5c79BC1EF5,
            0xffA54b4bFe0225C9b6A830aE1433516736e9a97a,
            0x60a1Cf0D617EeADbB48e488D9Ca3E74F50aB4b71,
            0xC2fea9942506CEF6d18b655Cb2de36d479Dc43bD,
            0x86b2D22C92ef56A9434A1b3758cC39a8D7FA8C1F,
            0xE79BB6F246a8493AC1D45926ab835FCCCDc32C78,
            0x383F9B2d080C58301D821e9F0EC5a35A17070bE6,
            0xb546807794dEdfd196a5d230856190d78cF31d04,
            0xeAa61217fbbaB972fEBFAEa8D62105139D0240E8,
            0x44B6A414e73fb7387Ca250F44D7e43cD7d6992c2,
            0x7f3F33B42b9734e61cb44424D130B5f6e09C9Db3,
            0x73380F4B3E6F4a8988688d1475D33CB1D46F6de0,
            0x3fe43D4ba0a5BAcC800c7E7E782466a27ab108bf,
            0x1bc48214A6e672FEA1eB115D9DC81B470E5F1173,
            0xd5bAd7c89028B3F7094e40DcCe83D4e6b3Fd9AA4,
            0xe50e2fe90745A8510491F89113959a1EF01AD400,
            0xbc0cF20Ac9Fc670fED9B3f230F2E8A2676451e37,
            0xa7739fd3d12ac7F16D8329AF3Ee407e19De10D8D,
            0x378416346914a8B530d26b621BdA7AE291ce264A,
            0x4fc424a840B5fB1BAf195963eC3737904440df1D,
            0xe6aB93d1c253d16733d52dD40b4929a6a04b2B08,
            0xe6cFc9d27f8bfC8ddcB86d75381cD21570A21B20,
            0x66F5263d51174bab17Ac2bda31E51F5bcF05a69A,
            0x61cf8d861ff3c939147c2aa1F694f9592Bf51983,
            0x4dd0cF20237deb5F2bE76340838B9e2D7c70E852,
            0xe17D6212eAa54D98187026A770dee96f7C264feC,
            0x7666FA065e0c44051411A5Ca3e85ad2C210C9e98,
            0xE0d5f9DA3613C047003b77cAa31270aBE3EdA6b0,
            0x64b3bc10e834905364178D6e23B296A5395EE111,
            0x9E59eb2059B44a0234b8454567482AE516926E8D,
            0x17dEc2AF8018f2F940D34787399eA123Ff292963,
            0xFA72D4083388D2c82A72b073ED4a0954C4079Dc3
        ];

        uint8 len = uint8(targets.length);
        for (uint8 i = 0; i < len; i++) {
            permissions.push(Permission(true, false));
        }

        controller.setPermissions(targets, permissions);
        
        vm.stopBroadcast();
    }
}
