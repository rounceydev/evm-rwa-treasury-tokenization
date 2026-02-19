const networkConfig = {
  1337: {
    name: "localhost",
    initialYieldRate: "400", // 4% APY in basis points
    minMintAmount: "1000", // Minimum mint amount
    minRedeemAmount: "1000", // Minimum redeem amount
  },
  11155111: {
    name: "sepolia",
    initialYieldRate: "400", // 4% APY in basis points
    minMintAmount: "1000",
    minRedeemAmount: "1000",
  },
};

const developmentChains = ["hardhat", "localhost"];

// Role constants (keccak256 hashes)
// These match the keccak256("ROLE_NAME") values in the contracts
const ROLE_ADMIN = "0x0000000000000000000000000000000000000000000000000000000000000000"; // DEFAULT_ADMIN_ROLE
const ROLE_MINTER = "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"; // keccak256("MINTER_ROLE")
const ROLE_REDEEMER = "0x..."; // keccak256("REDEEMER_ROLE") - calculated at runtime
const ROLE_PAUSER = "0x..."; // keccak256("PAUSER_ROLE") - calculated at runtime
const ROLE_ORACLE = "0x..."; // keccak256("ORACLE_ROLE") - calculated at runtime

module.exports = {
  networkConfig,
  developmentChains,
  ROLE_ADMIN,
  ROLE_MINTER,
  ROLE_REDEEMER,
  ROLE_PAUSER,
  ROLE_ORACLE,
};
