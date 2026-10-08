// SPDX-License-Identifier: MIT
pragma solidity 0.7.2;

// Parametric crop insurance for rapeseed, triggered by air humidity.
// Inspired by: https://github.com/lokmitra56/Crop_Insurance_Smart-Contract
//
// All ETH amounts are stored and transferred in wei (1 ETH = 1e18 wei).
// USD amounts are whole dollars. ethToUsdRate = USD per 1 ETH (e.g. 2500).

contract RapeseedHumidityInsurance {
    address public owner;
    uint256 public constant CONSECUTIVE_DAYS_THRESHOLD = 4; // days out of range needed to destroy the crop (assumption)
    uint256 public ethToUsdRate; // USD per 1 ETH

    struct Policy {
        bool isActive;                    // farmer has an active policy
        bool hasClaimPending;             // claim was triggered and not yet paid
        bool isPaid;                      // claim was paid out
        uint256 policyEndDate;            // unix timestamp
        uint256 claimAmount;              // insured amount in wei
        uint256 insuredValue;             // insured value in USD
        uint256 premium;                  // premium in wei
        uint256 consecutiveDaysOutOfRange;
        uint256 lastSubmissionTimestamp;
        uint256 minHumidityThreshold;     // % relative humidity
        uint256 maxHumidityThreshold;     // % relative humidity
        uint256 submissionInterval;       // seconds required between humidity submissions
    }

    mapping(address => Policy) public policies;

    event PolicyCreated(
        address indexed farmer,
        uint256 premiumInWei,
        uint256 insuredValueInUsd,
        uint256 minHumidityThreshold,
        uint256 maxHumidityThreshold,
        uint256 submissionInterval
    );
    event HumidityDataSubmitted(address indexed farmer, uint256 timestamp, uint256 humidityValue);
    event ClaimTriggered(address indexed farmer, uint256 payoutAmount);
    event ClaimPaid(address indexed farmer, uint256 payoutAmount);
    event PolicyCancelled(address indexed farmer, uint256 refundAmount);
    event EthToUsdRateUpdated(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyActivePolicyHolder() {
        require(policies[msg.sender].isActive, "No active policy found");
        _;
    }

    constructor(uint256 _initialEthToUsdRate) {
        require(_initialEthToUsdRate > 0, "Exchange rate must be greater than 0");
        owner = msg.sender;
        ethToUsdRate = _initialEthToUsdRate;
    }

    // Update the ETH/USD rate (set manually by the owner; no price oracle)
    function updateEthToUsdRate(uint256 _newRate) external onlyOwner {
        require(_newRate > 0, "Exchange rate must be greater than 0");
        ethToUsdRate = _newRate;
        emit EthToUsdRateUpdated(_newRate);
    }

    // Convert a USD amount to wei
    function usdToEth(uint256 _usdAmount) public view returns (uint256) {
        require(ethToUsdRate > 0, "Exchange rate not set");
        return (_usdAmount * 1e18) / ethToUsdRate;
    }

    // Contract balance in wei
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Create a policy for a farmer with the desired insured USD value
    function createPolicyForClient(
        address _clientAddress,
        uint256 _policyEndDate,
        uint256 _insuredValueInUsd,
        uint256 _minHumidityThreshold,
        uint256 _maxHumidityThreshold,
        uint256 _submissionInterval
    ) external payable onlyOwner {
        require(_clientAddress != address(0), "Invalid client address");
        require(_policyEndDate > block.timestamp, "Policy end date must be in the future");
        require(!policies[_clientAddress].isActive, "Client already has an active policy");
        require(_insuredValueInUsd > 0, "Insured value must be greater than 0");
        require(_minHumidityThreshold < _maxHumidityThreshold, "Invalid humidity thresholds");
        require(_submissionInterval > 0, "Submission interval must be greater than 0");

        uint256 insuredAmountInWei = usdToEth(_insuredValueInUsd);

        // Premium = 35% of the insured amount
        uint256 premiumInWei = (insuredAmountInWei * 35) / 100;
        require(msg.value >= premiumInWei, "Insufficient ETH sent for premium");

        policies[_clientAddress] = Policy({
            isActive: true,
            hasClaimPending: false,
            isPaid: false,
            policyEndDate: _policyEndDate,
            claimAmount: insuredAmountInWei,
            insuredValue: _insuredValueInUsd,
            premium: premiumInWei,
            consecutiveDaysOutOfRange: 0,
            lastSubmissionTimestamp: block.timestamp,
            minHumidityThreshold: _minHumidityThreshold,
            maxHumidityThreshold: _maxHumidityThreshold,
            submissionInterval: _submissionInterval
        });

        emit PolicyCreated(
            _clientAddress,
            premiumInWei,
            _insuredValueInUsd,
            _minHumidityThreshold,
            _maxHumidityThreshold,
            _submissionInterval
        );
    }

    // Cancel a policy (owner only); 50% of the premium is refunded
    function cancelPolicy(address _clientAddress) external onlyOwner {
        Policy storage policy = policies[_clientAddress];
        require(policy.isActive, "Policy is not active");
        require(block.timestamp < policy.policyEndDate, "Policy has already ended");

        policy.isActive = false;
        policy.hasClaimPending = false;
        policy.consecutiveDaysOutOfRange = 0;

        uint256 refundAmount = policy.premium / 2;
        payable(_clientAddress).transfer(refundAmount);

        emit PolicyCancelled(_clientAddress, refundAmount);
    }

    // Submit a humidity reading (called by the farmer's sensor)
    function submitHumidityData(uint256 _humidityValue) external onlyActivePolicyHolder {
        Policy storage policy = policies[msg.sender];
        require(block.timestamp <= policy.policyEndDate, "Policy has expired");
        require(
            block.timestamp >= policy.lastSubmissionTimestamp + policy.submissionInterval,
            "Already submitted data within the interval"
        );

        policy.lastSubmissionTimestamp = block.timestamp;
        emit HumidityDataSubmitted(msg.sender, block.timestamp, _humidityValue);

        bool isOutOfRange = _humidityValue < policy.minHumidityThreshold
            || _humidityValue > policy.maxHumidityThreshold;

        if (isOutOfRange) {
            policy.consecutiveDaysOutOfRange++;
            if (policy.consecutiveDaysOutOfRange >= CONSECUTIVE_DAYS_THRESHOLD && !policy.hasClaimPending) {
                policy.hasClaimPending = true;
                emit ClaimTriggered(msg.sender, policy.claimAmount);
            }
        } else {
            policy.consecutiveDaysOutOfRange = 0;
        }
    }

    // Withdraw the insured amount after a claim was triggered
    function withdrawClaim() external onlyActivePolicyHolder {
        Policy storage policy = policies[msg.sender];
        require(policy.hasClaimPending, "No pending claim");
        require(!policy.isPaid, "Claim already paid");
        require(address(this).balance >= policy.claimAmount, "Insufficient contract balance");

        policy.isPaid = true;
        policy.hasClaimPending = false;
        policy.consecutiveDaysOutOfRange = 0;
        policy.isActive = false; // one payout per policy

        payable(msg.sender).transfer(policy.claimAmount);
        emit ClaimPaid(msg.sender, policy.claimAmount);
    }

    // Owner adds ETH to cover future payouts
    function fundContract() external payable onlyOwner {}

    // Owner withdraws ETH (amount in wei)
    function withdrawFunds(uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance, "Insufficient balance");
        payable(owner).transfer(_amount);
    }

    receive() external payable {}
}
