// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";
import "../DevTreasury.sol";
import "../MultiTokenPresale.sol";

// Mock ERC20 tokens for testing on testnet
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        _mint(msg.sender, 1_000_000_000 * 10**6); // 1B USDT with 6 decimals
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000_000 * 10**6); // 1B USDC with 6 decimals
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {
        _mint(msg.sender, 10_000 * 10**18); // 10k WETH
    }
}

contract MockWBTC is ERC20 {
    constructor() ERC20("Wrapped Bitcoin", "WBTC") {
        _mint(msg.sender, 1_000 * 10**8); // 1k WBTC with 8 decimals
    }

    function decimals() public view override returns (uint8) {
        return 8;
    }
}

contract MockLINK is ERC20 {
    constructor() ERC20("ChainLink Token", "LINK") {
        _mint(msg.sender, 10_000_000 * 10**18); // 10M LINK
    }
}

contract MockWBNB is ERC20 {
    constructor() ERC20("Wrapped BNB", "WBNB") {
        _mint(msg.sender, 100_000 * 10**18); // 100k WBNB
    }
}

/**
 * @title DeployPresale
 * @notice Comprehensive deployment script for all presale contracts (excluding staking)
 * @dev Deploy with: forge script script/DeployPresale.s.sol:DeployPresale --rpc-url <RPC> --private-key <KEY> --broadcast
 */
contract DeployPresale is Script {
    // Deployed contracts
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    DevTreasury public devTreasury;
    MultiTokenPresale public presale;

    // Mock tokens (testnet only)
    MockUSDT public mockUSDT;
    MockUSDC public mockUSDC;
    MockWETH public mockWETH;
    MockWBTC public mockWBTC;
    MockLINK public mockLINK;
    MockWBNB public mockWBNB;

    // Treasury and authorization addresses
    address public constant PROJECT_TREASURY = 0x1321286BB1f31d4438F6E5254D2771B79a6A773e;
    address public constant OWNER_ADDRESS = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public constant BACKEND_SIGNER = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2; // Backend signer for vouchers

    // Presale parameters
    uint256 public constant PRESALE_RATE = 666_666_666_666_666_667; // ~666.67 tokens per USD (18 decimals)
    uint256 public constant MAX_TOKENS_FOR_PRESALE = 5_000_000_000 * 10**18; // 5B tokens

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Starting deployment...");
        console.log("Deployer: ", vm.addr(deployerPrivateKey));

        // Step 1: Deploy ESCROW Token
        console.log("\n=== Step 1: Deploying ESCROW Token ===");
        escrowToken = new EscrowToken();
        console.log("ESCROW Token deployed at:", address(escrowToken));

        // Step 2: Deploy mock tokens (testnet only - check if on testnet)
        console.log("\n=== Step 2: Deploying Mock Tokens (Testnet) ===");
        if (block.chainid == 11155111 || block.chainid == 31337) { // Sepolia or local
            mockUSDT = new MockUSDT();
            console.log("Mock USDT deployed at:", address(mockUSDT));

            mockUSDC = new MockUSDC();
            console.log("Mock USDC deployed at:", address(mockUSDC));

            mockWETH = new MockWETH();
            console.log("Mock WETH deployed at:", address(mockWETH));

            mockWBTC = new MockWBTC();
            console.log("Mock WBTC deployed at:", address(mockWBTC));

            mockLINK = new MockLINK();
            console.log("Mock LINK deployed at:", address(mockLINK));

            mockWBNB = new MockWBNB();
            console.log("Mock WBNB deployed at:", address(mockWBNB));
        }

        // Step 3: Deploy Authorizer for KYC voucher system
        console.log("\n=== Step 3: Deploying Authorizer ===");
        authorizer = new Authorizer(BACKEND_SIGNER, OWNER_ADDRESS);
        console.log("Authorizer deployed at:", address(authorizer));

        // Step 4: Calculate future presale address (for DevTreasury constructor)
        console.log("\n=== Step 4: Calculating Future Presale Address ===");
        address predictedPresaleAddress = vm.computeCreateAddress(vm.addr(deployerPrivateKey), vm.getNonce(vm.addr(deployerPrivateKey)) + 1);
        console.log("Predicted Presale Address:", predictedPresaleAddress);

        // Step 5: Deploy DevTreasury with predicted presale address
        console.log("\n=== Step 5: Deploying DevTreasury ===");
        devTreasury = new DevTreasury(predictedPresaleAddress);
        console.log("DevTreasury deployed at:", address(devTreasury));
        console.log("DevTreasury linked to future presale:", predictedPresaleAddress);

        // Step 6: Deploy MultiTokenPresale with DevTreasury address
        console.log("\n=== Step 6: Deploying Presale Contract ===");
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS_FOR_PRESALE,
            address(devTreasury)
        );
        console.log("Presale Contract deployed at:", address(presale));
        
        // Verify prediction was correct
        require(address(presale) == predictedPresaleAddress, "Presale address mismatch!");
        console.log("SUCCESS: Presale address matches prediction");

        // Step 7: Mint presale allocation to presale contract
        console.log("\n=== Step 7: Minting Presale Allocation ===");
        escrowToken.mintPresaleAllocation(address(presale));
        console.log("Presale allocation minted successfully");
        
        console.log("\n=== Configuration Steps (Owner Only) ===");
        console.log("NOTE: The following must be done by owner:", OWNER_ADDRESS);
        console.log("1. presale.updateAuthorizer(", address(authorizer), ")");
        console.log("2. presale.setVoucherSystemEnabled(true)");

        // Step 8: Display deployment summary
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Network Chain ID:", block.chainid);
        console.log("\n=== Core Contracts ===");
        console.log("ESCROW Token:", address(escrowToken));
        console.log("Authorizer:", address(authorizer));
        console.log("DevTreasury:", address(devTreasury));
        console.log("Presale Contract:", address(presale));
        console.log("\n=== Configuration ===");
        console.log("Project Treasury:", PROJECT_TREASURY);
        console.log("Owner Address:", OWNER_ADDRESS);
        console.log("Backend Signer:", BACKEND_SIGNER);
        console.log("Presale Rate:", PRESALE_RATE, "tokens per USD");
        console.log("Max Tokens for Presale:", MAX_TOKENS_FOR_PRESALE / 1e18, "billion");

        if (block.chainid == 11155111 || block.chainid == 31337) {
            console.log("\n========== TEST TOKENS (TESTNET) ==========");
            console.log("Mock USDT:", address(mockUSDT));
            console.log("Mock USDC:", address(mockUSDC));
            console.log("Mock WETH:", address(mockWETH));
            console.log("Mock WBTC:", address(mockWBTC));
            console.log("Mock LINK:", address(mockLINK));
            console.log("Mock WBNB:", address(mockWBNB));
        }

        console.log("\n========== NEXT STEPS ==========");
        console.log("1. Verify all deployed contract addresses");
        console.log("2. Configure mock token prices if on testnet");
        console.log("3. Enable voucher system: presale.toggleVoucherSystem()");
        console.log("4. Backend: Generate KYC vouchers using Authorizer signer key");
        console.log("5. Start presale when ready: presale.startPresale() or autoStartEscrowPresale()");
        console.log("6. After presale ends: DevTreasury.withdrawETH() and withdrawToken() distribute 4% fees");
        console.log("\nNOTE: All contracts deployed successfully with correct dependencies!");

        vm.stopBroadcast();

        console.log("\nDeployment completed successfully!");
    }
}
