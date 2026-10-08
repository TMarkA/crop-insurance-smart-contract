# Crop Insurance Smart Contract with a Raspberry Pi Sensor

This is a project I did at Otto von Guericke University Magdeburg. The idea was to build an insurance contract that works automatically, based on real sensor data. I used agriculture as the example: a humidity sensor on a Raspberry Pi measures the air, and the readings are sent to a smart contract on the blockchain. If the humidity stays too low or too high for too long, the crop is considered lost and the insurance pays out on its own, without anyone having to check the field.

The code was lightly cleaned up before I uploaded it here.

## Background

I picked rapeseed as the crop. Rapeseed suffers when the air is too dry for several days, and too much humidity brings fungal diseases. So the farmer and the insurer agree on a humidity range, for example 40 to 70 %. If the sensor reports values outside this range four days in a row, the contract assumes the harvest is destroyed and releases the insured amount to the farmer.

The four-day rule and the range are assumptions I made for the project, not agronomic values.

## How the parts fit together

```
DHT22 sensor  ->  Raspberry Pi (Python)  ->  Ganache (local Ethereum)  ->  Smart contract
```

### Sensor

A DHT22 humidity sensor is connected to the Raspberry Pi on GPIO pin 25. In a real setup it would sit on the field. For the project it was on the desk, and I changed the humidity by breathing on it.

### Python script

`sensor/humidity_to_contract.py` connects the sensor to the blockchain. It reads the humidity, shows the current value in a small window, and every minute sends it to the contract. To do that it uses web3.py to build a transaction calling `submitHumidityData()`, signs it with the farmer's wallet key and sends it to the network.

### Smart contract

`contracts/RapeseedHumidityInsurance.sol` is written in Solidity and contains the insurance logic:

- The insurer creates a policy for a farmer with the insured value in USD, the humidity range and an end date. The premium is 35 % of the insured value and is paid in ETH.
- Every humidity reading outside the range counts as one bad day. A normal reading resets the counter.
- After four bad days in a row the contract triggers a claim by itself.
- The farmer then calls `withdrawClaim()` and gets the insured amount.
- The insurer can also cancel a policy early (the farmer gets half of the premium back), add money to the payout pool and update the ETH/USD rate.

### Blockchain

I deployed the contract with Remix IDE to a local Ethereum network running in Ganache. Each reading, claim and payout is stored there as a transaction, so you can follow afterwards exactly what happened and when.

## Files

```
contracts/RapeseedHumidityInsurance.sol   the insurance contract (Solidity 0.7.2)
sensor/humidity_to_contract.py            sensor script for the Raspberry Pi
sensor/abi.json                           contract interface used by the script
.env.example                              template for addresses and keys
requirements.txt                          Python packages
```

## Running it

You need a Raspberry Pi with a DHT22 on GPIO 25, Python 3, [Ganache](https://archive.trufflesuite.com/ganache/) and [Remix IDE](https://remix.ethereum.org/).

1. Start Ganache. It gives you test accounts with fake ETH. Use one as the insurer and another one as the farmer.
2. Open the contract in Remix, compile it with version 0.7.2, choose "Dev - Ganache Provider" as environment and deploy it from the insurer account. The constructor needs the ETH/USD rate, e.g. 2500.
3. Call `fundContract()` with some ETH, then `createPolicyForClient()` for the farmer's address. For testing, a submission interval of 60 seconds works well.
4. On the Raspberry Pi:

   ```bash
   pip install -r requirements.txt
   cp .env.example .env
   python sensor/humidity_to_contract.py
   ```

   Fill in the contract address and the farmer's address and private key in `.env` first. If Ganache runs on another computer, start it on 0.0.0.0 and put that computer's IP into `GANACHE_URL`.

5. Keep the humidity outside the range for four readings, then call `withdrawClaim()` from the farmer account.

## Limitations

This is a prototype for a university course, so a few things are simplified:

- The farmer's own device sends the data, so in theory the farmer could fake it. A real product would need a trusted data source, for example an oracle service like Chainlink.
- The ETH/USD rate is entered by hand instead of coming from a price feed.
- The contract counts readings, not calendar days. The four days only match reality if the submission interval is set to 24 hours.
- Everything runs on a local test network.

## Tools used

Solidity, Python, web3.py, Raspberry Pi, DHT22, RPi.GPIO, Tkinter, Ganache, Remix IDE

## Credits

The contract was inspired by [lokmitra56/Crop_Insurance_Smart-Contract](https://github.com/lokmitra56/Crop_Insurance_Smart-Contract). The sensor code is based on Spanner, G. (2017), Franzis Raspberry Pi Maker Kit Elektronik: Messen, Steuern und Regeln mit dem Raspberry Pi.

## License

MIT
