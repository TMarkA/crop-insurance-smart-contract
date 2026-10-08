"""
Reads air humidity from a DHT22 sensor on a Raspberry Pi, shows it in a small
Tkinter window and submits it to the RapeseedHumidityInsurance smart contract
running on a local Ganache blockchain.

Sensor reading based on:
Spanner, G. (2017). Franzis Raspberry Pi Maker Kit Elektronik:
Messen, Steuern und Regeln mit dem Raspberry Pi.
"""

import json
import os
import time
from pathlib import Path

import tkinter as tk
from dotenv import load_dotenv
from RPi import GPIO
from web3 import Web3

# ---------------------------------------------------------------------------
# Configuration (values come from the .env file, see .env.example)
# ---------------------------------------------------------------------------
load_dotenv()

GANACHE_URL = os.getenv("GANACHE_URL", "http://127.0.0.1:7545")
CHAIN_ID = int(os.getenv("CHAIN_ID", "1337"))
CONTRACT_ADDRESS = os.environ["CONTRACT_ADDRESS"]
WALLET_ADDRESS = os.environ["WALLET_ADDRESS"]  # farmer wallet = policy holder
PRIVATE_KEY = os.environ["PRIVATE_KEY"]        # never commit this
SUBMIT_INTERVAL_SEC = int(os.getenv("SUBMIT_INTERVAL_SEC", "60"))

# Sensor setup
SENSOR_PIN = 25      # GPIO pin (BCM numbering) connected to the DHT22
NUM_CYCLES = 100     # number of pulses counted per measurement
CAL = 100            # calibration factor

GPIO.setmode(GPIO.BCM)
GPIO.setup(SENSOR_PIN, GPIO.IN)

# ---------------------------------------------------------------------------
# Blockchain connection
# ---------------------------------------------------------------------------
web3 = Web3(Web3.HTTPProvider(GANACHE_URL))
if not web3.is_connected():
    raise ConnectionError(f"Failed to connect to Ganache at {GANACHE_URL}. Is Ganache running?")

abi_path = Path(__file__).parent / "abi.json"
contract_abi = json.loads(abi_path.read_text())
contract = web3.eth.contract(
    address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=contract_abi
)
wallet_address = Web3.to_checksum_address(WALLET_ADDRESS)

last_submission = 0.0


def submit_humidity(humidity):
    """Send one humidity reading to the smart contract."""
    humidity_int = int(humidity)  # contract expects a whole number (%)
    tx_function = contract.functions.submitHumidityData(humidity_int)

    tx = tx_function.build_transaction({
        "chainId": CHAIN_ID,
        "from": wallet_address,
        "gas": tx_function.estimate_gas({"from": wallet_address}),
        "gasPrice": web3.to_wei("20", "gwei"),
        "nonce": web3.eth.get_transaction_count(wallet_address),
    })

    signed_tx = web3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Submitted {humidity_int}% (tx {tx_hash.hex()}, block {receipt.blockNumber})")


def read_humidity():
    """Read the DHT22 sensor and return % relative humidity."""
    t_start = time.time()
    for _ in range(NUM_CYCLES):
        GPIO.wait_for_edge(SENSOR_PIN, GPIO.FALLING)
    t_stop = time.time()
    return int(CAL / (t_stop - t_start)) / 10.0


def update(label):
    """Read the sensor, update the window and submit to the contract when due."""
    global last_submission

    humidity = read_humidity()
    label.config(text=f"Rel. Feuchte: {humidity}%")

    if time.time() - last_submission >= SUBMIT_INTERVAL_SEC:
        try:
            submit_humidity(humidity)
            last_submission = time.time()
        except Exception as e:  # e.g. contract rejects a too-early submission
            print(f"Submission failed: {e}")

    label.after(1000, update, label)


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
root = tk.Tk()
root.title("Hygrometer")
root.geometry("420x60")

label = tk.Label(root, text="", font=("Arial", 30, "normal"))
label.pack()

try:
    update(label)
    root.mainloop()
finally:
    GPIO.cleanup()
