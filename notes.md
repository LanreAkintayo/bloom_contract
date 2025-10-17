So, to create deals, I'm going to create a two tokens for example
1. USDC
2. DAI

So, in total, there will be 3 tokens that would be used to create Deals;
1. Native Token (ETH, BNB, S)
2. USDC
3. DAI


For the price feeds, I have to supply prices for each of them;
1. NATIVE TOKEN --> Check price online
2. USDC - $1 --> decimals = 8
3. DAI - $1  --> decimals = 18


Create a mock vrf for random numbers

**Disputes**
The token address that was used in creating deal will be used to open dispute


**Appeal**
The token address that was used in creating deal will be used to appeal


**Don't Forget**
Don't forget to lock staked amount of the jurors oo
Evidence should have an ID or something

1. Add vrf timeout
2. select juror should be for everybody
3. add more getters



while computing score, these are things to look out for;
we want to keep track of the max stake and max reputation. When you register, stakeMore, withdraw stake, distribute rewards and reputation, your max stake and max reputaiton changes
when stake and reputation changes, your scores will also be recomputed.
when score gets recomputed, the experienced pool and the newbie pool will also get recomputed.


 forge script script/deploy/DeployAll.s.sol:DeployAll   --rpc-url $SEPOLIA_RPC_URL   --broadcast   --private-key $PRIVATE_KEY 

  forge verify-contract --chain sepolia 0xCeDDfC31c1Ac1CA4F9D309eA9428E098e67f5531 src/core/disputes/JurorManager.sol:JurorManager $ETHERSCAN_API_KEY

