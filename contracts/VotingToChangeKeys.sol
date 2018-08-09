pragma solidity ^0.4.24;

import "./interfaces/IBallotsStorage.sol";
import "./interfaces/IKeysManager.sol";
import "./interfaces/IVotingToChangeKeys.sol";
import "./abstracts/VotingToChange.sol";
import "./abstracts/EnumKeyTypes.sol";


contract VotingToChangeKeys is IVotingToChangeKeys, VotingToChange, EnumKeyTypes {
    string internal constant AFFECTED_KEY = "affectedKey";
    string internal constant AFFECTED_KEY_TYPE = "affectedKeyType";
    string internal constant BALLOT_TYPE = "ballotType";
    string internal constant MINING_KEY = "miningKey";
    string internal constant NEW_PAYOUT_KEY = "newPayoutKey";
    string internal constant NEW_VOTING_KEY = "newVotingKey";

    function createBallot(
        uint256 _startTime,
        uint256 _endTime,
        address _affectedKey,
        uint256 _affectedKeyType,
        address _miningKey,
        uint256 _ballotType,
        string _memo
    ) public returns(uint256) {
        require(_getBallotsStorage().areKeysBallotParamsValid(
            _ballotType,
            _affectedKey,
            _affectedKeyType,
            _miningKey
        ));
        uint256 ballotId = _createBallot(_ballotType, _startTime, _endTime, _memo);
        _setAffectedKey(ballotId, _affectedKey);
        _setAffectedKeyType(ballotId, _affectedKeyType);
        _setMiningKey(ballotId, _miningKey);
        _setBallotType(ballotId, _ballotType);
        return ballotId;
    }

    function createBallotToAddNewValidator(
        uint256 _startTime,
        uint256 _endTime,
        address _newMiningKey,
        address _newVotingKey,
        address _newPayoutKey,
        string _memo
    ) public returns(uint256) {
        IKeysManager keysManager = _getKeysManager();
        require(keysManager.miningKeyByVoting(_newVotingKey) == address(0));
        require(keysManager.miningKeyByPayout(_newPayoutKey) == address(0));
        require(_newVotingKey != _newMiningKey);
        require(_newPayoutKey != _newMiningKey);
        if (_newVotingKey != address(0) && _newPayoutKey != address(0)) {
            require(_newVotingKey != _newPayoutKey);
        }
        uint256 ballotId = createBallot(
            _startTime,
            _endTime,
            _newMiningKey, // _affectedKey
            uint256(KeyTypes.MiningKey), // _affectedKeyType
            address(0), // _miningKey
            uint256(BallotTypes.KeyAdding), // _ballotType
            _memo
        );
        _setNewVotingKey(ballotId, _newVotingKey);
        _setNewPayoutKey(ballotId, _newPayoutKey);
        return ballotId;
    }

    function getBallotInfo(uint256 _id) public view returns(
        uint256 startTime,
        uint256 endTime,
        address affectedKey,
        uint256 affectedKeyType,
        address newVotingKey,
        address newPayoutKey,
        address miningKey,
        uint256 totalVoters,
        int256 progress,
        bool isFinalized,
        uint256 ballotType,
        address creator,
        string memo,
        bool canBeFinalizedNow
    ) {
        startTime = _getStartTime(_id);
        endTime = _getEndTime(_id);
        affectedKey = _getAffectedKey(_id);
        affectedKeyType = _getAffectedKeyType(_id);
        newVotingKey = _getNewVotingKey(_id);
        newPayoutKey = _getNewPayoutKey(_id);
        miningKey = _getMiningKey(_id);
        totalVoters = _getTotalVoters(_id);
        progress = _getProgress(_id);
        isFinalized = _getIsFinalized(_id);
        ballotType = _getBallotType(_id);
        creator = _getCreator(_id);
        memo = _getMemo(_id);
        canBeFinalizedNow = _canBeFinalizedNow(_id);
    }

    function migrateBasicOne(
        uint256 _id,
        address _prevVotingToChange,
        uint8 _quorumState,
        uint256 _index,
        address _creator,
        string _memo,
        address[] _voters
    ) public {
        _migrateBasicOne(
            _id,
            _prevVotingToChange,
            _quorumState,
            _index,
            _creator,
            _memo,
            _voters
        );
        IVotingToChangeKeysPrev prev = IVotingToChangeKeysPrev(_prevVotingToChange);
        _setBallotType(_id, prev.getBallotType(_id));
        _setAffectedKey(_id, prev.getAffectedKey(_id));
        _setAffectedKeyType(_id, prev.getAffectedKeyType(_id));
        _setMiningKey(_id, prev.getMiningKey(_id));
        //_setNewVotingKey(_id, prev.getNewVotingKey(_id));
        //_setNewPayoutKey(_id, prev.getNewPayoutKey(_id));
    }

    // solhint-disable code-complexity
    function _finalizeAdding(uint256 _id) internal returns(bool) {
        IKeysManager keysManager = _getKeysManager();

        address affectedKey = _getAffectedKey(_id);
        uint256 affectedKeyType = _getAffectedKeyType(_id);
        
        if (affectedKeyType == uint256(KeyTypes.MiningKey)) {
            address newVotingKey = _getNewVotingKey(_id);
            if (keysManager.miningKeyByVoting(newVotingKey) != address(0)) {
                return false;
            }

            address newPayoutKey = _getNewPayoutKey(_id);
            if (keysManager.miningKeyByPayout(newPayoutKey) != address(0)) {
                return false;
            }

            if (!keysManager.addMiningKey(affectedKey)) {
                return false;
            }

            if (newVotingKey != address(0)) {
                keysManager.addVotingKey(newVotingKey, affectedKey);
            }

            if (newPayoutKey != address(0)) {
                keysManager.addPayoutKey(newPayoutKey, affectedKey);
            }

            return true;
        } else if (affectedKeyType == uint256(KeyTypes.VotingKey)) {
            if (keysManager.miningKeyByVoting(affectedKey) != address(0)) {
                return false;
            }
            return keysManager.addVotingKey(affectedKey, _getMiningKey(_id));
        } else if (affectedKeyType == uint256(KeyTypes.PayoutKey)) {
            if (keysManager.miningKeyByPayout(affectedKey) != address(0)) {
                return false;
            }
            return keysManager.addPayoutKey(affectedKey, _getMiningKey(_id));
        }
        return false;
    }
    // solhint-enable code-complexity

    function _finalizeBallotInner(uint256 _id) internal returns(bool) {
        uint256 ballotType = _getBallotType(_id);
        if (ballotType == uint256(BallotTypes.KeyAdding)) {
            return _finalizeAdding(_id);
        } else if (ballotType == uint256(BallotTypes.KeyRemoval)) {
            return _finalizeRemoval(_id);
        } else if (ballotType == uint256(BallotTypes.KeySwap)) {
            return _finalizeSwap(_id);
        }
        return false;
    }

    function _finalizeRemoval(uint256 _id) internal returns(bool) {
        IKeysManager keysManager = _getKeysManager();
        uint256 affectedKeyType = _getAffectedKeyType(_id);
        if (affectedKeyType == uint256(KeyTypes.MiningKey)) {
            return keysManager.removeMiningKey(_getAffectedKey(_id));
        } else if (affectedKeyType == uint256(KeyTypes.VotingKey)) {
            return keysManager.removeVotingKey(_getMiningKey(_id));
        } else if (affectedKeyType == uint256(KeyTypes.PayoutKey)) {
            return keysManager.removePayoutKey(_getMiningKey(_id));
        }
        return false;
    }

    function _finalizeSwap(uint256 _id) internal returns(bool) {
        IKeysManager keysManager = _getKeysManager();
        uint256 affectedKeyType = _getAffectedKeyType(_id);
        if (affectedKeyType == uint256(KeyTypes.MiningKey)) {
            return keysManager.swapMiningKey(_getAffectedKey(_id), _getMiningKey(_id));
        } else if (affectedKeyType == uint256(KeyTypes.VotingKey)) {
            address newVotingKey = _getAffectedKey(_id);
            if (keysManager.miningKeyByVoting(newVotingKey) != address(0)) {
                return false;
            }
            return keysManager.swapVotingKey(newVotingKey, _getMiningKey(_id));
        } else if (affectedKeyType == uint256(KeyTypes.PayoutKey)) {
            address newPayoutKey = _getAffectedKey(_id);
            if (keysManager.miningKeyByPayout(newPayoutKey) != address(0)) {
                return false;
            }
            return keysManager.swapPayoutKey(newPayoutKey, _getMiningKey(_id));
        }
        return false;
    }

    function _getAffectedKey(uint256 _id) internal view returns(address) {
        return addressStorage[
            keccak256(abi.encode(VOTING_STATE, _id, AFFECTED_KEY))
        ];
    }

    function _getAffectedKeyType(uint256 _id) internal view returns(uint256) {
        return uintStorage[
            keccak256(abi.encode(VOTING_STATE, _id, AFFECTED_KEY_TYPE))
        ];
    }

    function _getBallotType(uint256 _id) internal view returns(uint256) {
        return uintStorage[
            keccak256(abi.encode(VOTING_STATE, _id, BALLOT_TYPE))
        ];
    }

    function _getMiningKey(uint256 _id) internal view returns(address) {
        return addressStorage[
            keccak256(abi.encode(VOTING_STATE, _id, MINING_KEY))
        ];
    }

    function _getNewPayoutKey(uint256 _id) internal view returns(address) {
        return addressStorage[
            keccak256(abi.encode(VOTING_STATE, _id, NEW_PAYOUT_KEY))
        ];
    }

    function _getNewVotingKey(uint256 _id) internal view returns(address) {
        return addressStorage[
            keccak256(abi.encode(VOTING_STATE, _id, NEW_VOTING_KEY))
        ];
    }

    function _setAffectedKey(uint256 _ballotId, address _value) internal {
        addressStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, AFFECTED_KEY))
        ] = _value;
    }

    function _setAffectedKeyType(uint256 _ballotId, uint256 _value) internal {
        uintStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, AFFECTED_KEY_TYPE))
        ] = _value;
    }

    function _setBallotType(uint256 _ballotId, uint256 _value) internal {
        uintStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, BALLOT_TYPE))
        ] = _value;
    }

    function _setMiningKey(uint256 _ballotId, address _value) internal {
        addressStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, MINING_KEY))
        ] = _value;
    }

    function _setNewPayoutKey(uint256 _ballotId, address _value) internal {
        addressStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, NEW_PAYOUT_KEY))
        ] = _value;
    }

    function _setNewVotingKey(uint256 _ballotId, address _value) internal {
        addressStorage[
            keccak256(abi.encode(VOTING_STATE, _ballotId, NEW_VOTING_KEY))
        ] = _value;
    }

}
