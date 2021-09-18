require("@nomiclabs/hardhat-waffle")
// require("dotenv").config()

// const { MNEMONIC } = process.env
const MNEMONIC = "test test test test test test test test test test test test"

module.exports = {
  defaultNetwork: 'okexchain',
  networks: {
    okexchain: {
      url: "https://exchainrpc.okex.org",
      chainId: 66,
      accounts: {
        mnemonic: MNEMONIC,
      },
      gasPrice: 1e9,
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          metadata: {
            bytecodeHash: 'none',
          },
        },
      },
    ],
  },
  paths: {
    artifacts: "./build/artifacts",
    cache: "./build/cache",
    sources: "./contracts",
  },
}
