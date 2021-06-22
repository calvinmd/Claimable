# Claimable
## What is Claimable?
Claimable is a smart contract that allows you to schedule your token release or transfer. It works similar to a stock option grant, where you specify a cliff and a vesting period. This could be used for common use cases such as investor token release and incentive token grants. It works on all EVM-compatible blockchains, such as Ethereum and its testnets, Binance Smart Chain, and Avalanche, etc.

Watch the video demo here: https://youtu.be/_mL4ejo-Oks

## Supported methods
### Create (transaction)
As a grantor, you can create a grant `ticket` where you specify the following
- **token**: the address of the ERC20 token you are granting
- **beneficiary**: the recipient of this token grant
- **cliff**: you can specify a cliff (in number of days) or set it to 0 to make it immediately available
- **vesting**: the number of days for the entire amount to be vested
- **amount**: the number of tokens you are granting
- **irrevocable**: if set to `true`, you will not be able to revoke
### batchCreateSameAmount (transaction)
As a grantor, you can create a batch of `tickets` where you specify the following
- **token**: the address of the ERC20 token you are granting
- **beneficiaries**: array of recipients
- **cliff**: you can specify a cliff (in number of days) or set it to 0 to make it immediately available
- **vesting**: the number of days for the entire amount to be vested
- **amount**: the number of tokens you are granting
- **irrevocable**: if set to `true`, you will not be able to revoke
### batchCreate (transaction)
As a grantor, you can create a batch of `tickets` where you specify the following
- **token**: the address of the ERC20 token you are granting
- **beneficiaries**: array of recipients
- **cliff**: you can specify a cliff (in number of days) or set it to 0 to make it immediately available
- **vesting**: the number of days for the entire amount to be vested
- **amounts**: the number array of tokens you are granting for each beneficiary
- **irrevocable**: if set to `true`, you will not be able to revoke

### Revoke (transaction)
- You may revoke a grant by calling it with a ticket number. The method will transfer the remaining balance of the tokens back to the grantor wallet address, and the beneficiary will no longer be able to make a claim

### Claim (transaction)
- You can claim your ticket for all the available tokens. You will be responsible for paying for the gas fee

### Available (query)
- Display the number of tokens that are available to the beneficiary for the ticket. Only grantor and beneficiary can query

### hasCliffed (query)
- Check if the ticket has cliffed or not. Only grantor and beneficiary can query

### myBeneficiaryTickets (query)
- List all ticket numbers that you are the beneficiary

### myGrantorTickets (query)
- List all ticket numbers that you are the grantor

### viewTickets (query)
- enter ticket number to view Ticket struct


## How do I try it?
- It is available on Rinkey testnet: [0xB84cda1Bf76328EfEEB0FE40139177790866F210](https://rinkeby.etherscan.io/address/0xB84cda1Bf76328EfEEB0FE40139177790866F210#writeContract)
- You will need first to approve the smart contract with your token
- Use the `Write Contract` tab to `create`, `claim` or `revoke`
- You can use the `Read Contract` tab for queries

## When can I use it on the mainnet?
- I am still building the user interface, will launch to mainnet after UI is completed
- Further testing and security audit will be performed
- **Disclaimer**: There is absolutely no warranty or guarantee. Use at your own risk.
