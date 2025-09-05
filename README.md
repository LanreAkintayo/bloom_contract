## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```


State variables

Constants / immutables

Errors

Events

Modifiers

Constructor

External/public functions

Internal/private functions


Fallback/receive functions

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract
​
// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions
​
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions



-- finish dispute logic is not completed

-- Not done anything to missed or missedCount
-- not done anything on startTime
-- when finalizing dispute. Make sure you punish all the candidates with missed votes.
-- Change the rule to ensure that they can handle more than one dispute at the same time
-- For the stake amount, always ensure that before they get selected, if they vote wrongly, there would still be amount of stake that will be slashed from their stake amount
-- To remove stake, they cannot remove from what they have in store.



// Conditions to pop from active juror addresses
1. You are currently selected for a dispute
2. You have missed votes up to 3 times
3. You 