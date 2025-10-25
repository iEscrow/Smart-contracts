// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowTresury.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 10_000_000_000 * 1e18); // Mint 10B tokens for testing
    }
}

contract FullSetupScript {
    function run() external {
        // --------------------------
        // 1️⃣ Deploy mock token
        // --------------------------
        MockToken token = new MockToken();

        // --------------------------
        // 2️⃣ Deploy EscrowMultiTreasury
        // --------------------------
        // LP & Marketing test addresses (use your local accounts)
        address lp = 0x5f5868Bb7E708aAb9C25c80AEBFA0131735233af;
        address mkt = 0xa315b46cA80982278eD28A3496718B1524Df467b;

        EscrowMultiTreasury escrow = new EscrowMultiTreasury(
            address(token),
            lp,
            mkt
        );

        // --------------------------
        // 3️⃣ Fund the treasury
        // --------------------------
        // Approve and transfer tokens to the treasury
        token.approve(address(escrow), 9_400_000_000 * 1e18);
        escrow.fund();

        // --------------------------
        // 4️⃣ Set team beneficiaries
        // --------------------------
        // Initialize arrays for team addresses and allocations
        address[] memory addrs = new address[](28);
        uint256[] memory amts = new uint256[](28);

        // Team addresses
        addrs[0]  = 0x04435410a78192baAfa00c72C659aD3187a2C2cF;
        addrs[1]  = 0x9005132849bC9585A948269D96F23f56e5981A61;
        addrs[2]  = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74;
        addrs[3]  = 0x507541B0Caf529a063E97c6C145E521d3F394264;
        addrs[4]  = 0x04D83B2BdF89fe4C781Ec8aE3D672c610080B319;
        addrs[5]  = 0xA5F415dA5b5E63aFc8f0c378F047671592A842Fe;
        addrs[6]  = 0x77aB60050DFA1E2764366BC52A83EEab1E1a35ad;
        addrs[7]  = 0x543ed850e2df486e2B37A602926C12b97b910405;
        addrs[8]  = 0xC259811079610E1a60Bf5ebCb7d0F8Ac3857b1d6;
        addrs[9]  = 0x68f5d8e68abDf9c6C0233DE2bdAda5e18CC6634d;
        addrs[10] = 0x30D3d7C9A4276a5A63EE9c36d6C69CEA3e6B08da;
        addrs[11] = 0x69873ef24F48205036177b03628f8727b8445999;
        addrs[12] = 0x790823b7bd58f1b84D99Cd7d474C24Af894deE2c;
        addrs[13] = 0x9f1Ec9342a567E16703076385763f49aABFFA15e;
        addrs[14] = 0x687B309a341B453084539f83081B292462a92c4D;
        addrs[15] = 0x01553Bc974Ed86f892813E535B1Ed03a384212F5;
        addrs[16] = 0xE0C7f8329F0d401bE419A2F15371aB2DAfe3f7c4;
        addrs[17] = 0x6fBa9db2Ca25cC280ec559aD44540bD7B061a66B;
        addrs[18] = 0xfa44D3E91aBf1327566a2c34E9f46C332B412634;
        addrs[19] = 0x5d8d1EA81af164051F341fB6224F243775Dea07a;
        addrs[20] = 0x37006C70d09fc59abF3EeE7a1B244d6c831cb281;
        addrs[21] = 0xC6808526ed02162668Ec35D7C0b16f1C99802534;
        addrs[22] = 0x91C665974574a51bd9Eb23aE79B26C58415eF6b2;
        addrs[23] = 0x658ba47F95541d8919C46b3488dE12be7587167D;
        addrs[24] = 0x54920dEb99489F36AB7204F727E20B72fB391e7b;
        addrs[25] = 0x4C11b6D0d1aD06F95966372014097AE3411cE7b9;
        addrs[26] = 0x277cAebe8E2d2284752d75853Fe70aF00dE893ac;
        addrs[27] = 0x2C9760E45abB8879A6ac86d3CA19012Cf513738d;

        // Allocations
        for (uint256 i = 0; i < 10; i++) {
            amts[i] = 10_000_000 * 1e18;
        }
        for (uint256 i = 10; i < 28; i++) {
            amts[i] = 50_000_000 * 1e18;
        }

        escrow.batchSetTeam(addrs, amts);

        // --------------------------
        // 5️⃣ Lock the treasury
        // --------------------------
        escrow.lock();
    }
}
