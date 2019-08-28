pragma solidity >=0.4.22 <0.6.0;

contract PredictionMarket {
    
    struct Forecast {
        uint value;
        uint stake;
        uint distance;
    }
    
    address owner;
    uint deadline;
    
    address[] participants;
    // The following mapping stores the index of each participant
    // in the above array. This is needed for removing participants.
    mapping (address => uint) index;
    
    mapping (address => Forecast[]) forecasts;
    uint numberOfForecasts;
    
    mapping (address => uint) pendingRefunds;
    uint sumOfPendingRefunds;
    
    uint oracleValue;
    uint maxDistFromOracleValue;
    bool marketClosed;
    uint sumOfFinalStakes;
    uint sumOfRewardWeights;
    mapping (address => uint) pendingRewardWeight;
    
    constructor(uint _timeIntervalInMinutes) public {
        deadline = now + _timeIntervalInMinutes * 1 minutes;
        owner = msg.sender;
        marketClosed = false;
        numberOfForecasts = 0;
        sumOfPendingRefunds = 0;
        maxDistFromOracleValue = 0;
        sumOfRewardWeights = 0;
    }
    
    modifier onlyBefore(uint _time) {
        require(now < _time, "Deadline has passed!");
        _;
    }
    
    modifier onlyAfter(uint _time) {
        require(now >= _time, "Deadline has not been reached yet!");
        _;
    }
    
    modifier onlyBy(address _address) {
        require(msg.sender == _address, "Unauthorized sender!");
        _;
    }
    
    modifier onlyIfMarketOpen() {
        require(marketClosed == false, "Market is closed!");
        _;
    }
    
    modifier onlyIfMarketClosed() {
        require(marketClosed == true, "Market is still open!");
        _;
    }
    
    function addForecast(uint _value) public payable onlyBefore(deadline) {
        require(msg.value > 0, "No stake received!");
        Forecast memory newForecast = Forecast({value: _value, stake: msg.value, distance: 0});
        if (forecasts[msg.sender].length == 0) {
            participants.push(msg.sender);
            index[msg.sender] = participants.length-1;
        }
        forecasts[msg.sender].push(newForecast);
        numberOfForecasts += 1;
    }
    
    // When a participant removes a forecast, it's stake is added to their pending
    // refunds. Then, their forecasts array is shifted to the left to fill the gap.
    // This function only takes an array index as a participant-specific forecast id.
    // Thus, maintaining the same order of forecasts on the client side is necessary.
    function removeForecast(uint _index) public onlyBefore(deadline) {
        uint length = forecasts[msg.sender].length;
        require(length > 0, "You have no forecasts!");
        require(_index < length, "Index out of range!");
        
        pendingRefunds[msg.sender] += forecasts[msg.sender][_index].stake;
        sumOfPendingRefunds += forecasts[msg.sender][_index].stake;
        
        for (uint i = _index; i < length - 1; i++) {
            forecasts[msg.sender][i] = forecasts[msg.sender][i+1];
        }
        delete forecasts[msg.sender][length-1];
        forecasts[msg.sender].length--;
        numberOfForecasts--;
        
        // removing the participant if they have no more forecasts
        if (forecasts[msg.sender].length == 0) {
            uint tempLength = participants.length;
            index[participants[tempLength-1]] = index[msg.sender];
            participants[index[msg.sender]] = participants[tempLength-1];
            delete participants[tempLength-1];
            participants.length--;
        }
    }
    
    function payOutRefunds() public {
        require(pendingRefunds[msg.sender] > 0, "You have no pending refunds.");
        uint amount = pendingRefunds[msg.sender];
        pendingRefunds[msg.sender] = 0;
        sumOfPendingRefunds -= amount;
        msg.sender.transfer(amount);        
    }
    
    function closeMarket(uint _oracleValue) public onlyBy(owner) onlyAfter(deadline) onlyIfMarketOpen() {
        oracleValue = _oracleValue;
        sumOfFinalStakes = address(this).balance - sumOfPendingRefunds;
        calcResults();
        marketClosed = true;
    }
    
    function calcResults() internal {
        
        // finding maximum distance from oracleValue among forecasts
        for (uint i = 0; i < participants.length; i++) {
            for (uint j=0; j < forecasts[participants[i]].length; j++) {
                if (forecasts[participants[i]][j].value >= oracleValue) {
                    forecasts[participants[i]][j].distance = forecasts[participants[i]][j].value - oracleValue;
                } else {
                    forecasts[participants[i]][j].distance = oracleValue - forecasts[participants[i]][j].value;
                }
                if (forecasts[participants[i]][j].distance > maxDistFromOracleValue) {
                    maxDistFromOracleValue = forecasts[participants[i]][j].distance;
                }
            }
        }
        
        // calculating reward weight for each participant
        for (uint i = 0; i < participants.length; i++) {
            Forecast[] memory forecasts_i = forecasts[participants[i]];
            uint rewardWeight_i = 0;
            for (uint j=0; j < forecasts_i.length; j++) {
                rewardWeight_i += (maxDistFromOracleValue - forecasts_i[j].distance) * forecasts_i[j].stake;
            }
            pendingRewardWeight[participants[i]] = rewardWeight_i;
            sumOfRewardWeights += rewardWeight_i;
        }
    }
    
    function payOutReward() public onlyIfMarketClosed() {
        require(pendingRewardWeight[msg.sender] > 0, "You have no rewards!");
        uint rewardWeight = pendingRewardWeight[msg.sender];
        // to avoid re-entrancy attack the state of the reward is set as paid at first
        pendingRewardWeight[msg.sender] = 0;
        uint reward = (rewardWeight * sumOfFinalStakes) / sumOfRewardWeights;
        msg.sender.transfer(reward);
    }
}
