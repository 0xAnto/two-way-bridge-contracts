/*

  Copyright 2019 Wanchain Foundation.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

//                            _           _           _
//  __      ____ _ _ __   ___| |__   __ _(_)_ __   __| | _____   __
//  \ \ /\ / / _` | '_ \ / __| '_ \ / _` | | '_ \@/ _` |/ _ \ \ / /
//   \ V  V / (_| | | | | (__| | | | (_| | | | | | (_| |  __/\ V /
//    \_/\_/ \__,_|_| |_|\___|_| |_|\__,_|_|_| |_|\__,_|\___| \_/
//
//  Code style according to: https://github.com/wanchain/wanchain-token/blob/master/style-guide.rst

pragma solidity ^0.4.24;

import "../lib/SafeMath.sol";
import "../components/Owned.sol";
import "./CreateGpkStorage.sol";
import "./lib/GpkLib.sol";

contract CreateGpkDelegate is CreateGpkStorage, Owned {
    using SafeMath for uint;

    /**
     *
     * EVENTS
     *
     */

    /// @notice                           event for storeman submit poly commit
    /// @param groupId                    storeman group id
    /// @param round                      group negotiate round
    /// @param curveIndex                 signature curve index
    /// @param storeman                   storeman address
    event SetPolyCommitLogger(bytes32 indexed groupId, uint8 indexed round, uint8 curveIndex, address storeman);

    /// @notice                           event for storeman submit encoded sij
    /// @param groupId                    storeman group id
    /// @param round                      group negotiate round
    /// @param curveIndex                 signature curve index
    /// @param src                        src storeman address
    /// @param dest                       dest storeman address
    event SetEncSijLogger(bytes32 indexed groupId, uint8 indexed round, uint8 curveIndex, address src, address dest);

    /// @notice                           event for storeman submit result of checking encSij
    /// @param groupId                    storeman group id
    /// @param round                      group negotiate round
    /// @param curveIndex                 signature curve index
    /// @param src                        src storeman address
    /// @param dest                       dest storeman address
    /// @param isValid                    whether encSij is valid
    event SetCheckStatusLogger(bytes32 indexed groupId, uint8 indexed round, uint8 curveIndex, address src, address dest, bool isValid);

    /// @notice                           event for storeman reveal sij
    /// @param groupId                    storeman group id
    /// @param round                      group negotiate round
    /// @param curveIndex                 signature curve index
    /// @param src                        src storeman address
    /// @param dest                       dest storeman address
    event RevealSijLogger(bytes32 indexed groupId, uint8 indexed round, uint8 curveIndex, address src, address dest);

    /**
    *
    * MANIPULATIONS
    *
    */

    /// @notice                           function for set smg contract address
    /// @param smgAddr                    smg contract address
    function setDependence(address smgAddr)
        external
        onlyOwner
    {
        require(smgAddr != address(0), "Invalid smg");
        smg = IStoremanGroup(smgAddr);
    }

    /// @notice                           function for set period
    /// @param groupId                    group id
    /// @param ployCommitPeriod           ployCommit period
    /// @param defaultPeriod              default period
    /// @param negotiatePeriod            negotiate period
    function setPeriod(bytes32 groupId, uint32 ployCommitPeriod, uint32 defaultPeriod, uint32 negotiatePeriod)
        external
        onlyOwner
    {
        GpkTypes.Group storage group = groupMap[groupId];
        group.ployCommitPeriod = ployCommitPeriod;
        group.defaultPeriod = defaultPeriod;
        group.negotiatePeriod = negotiatePeriod;
    }

    /// @notice                           function for set smg contract address
    /// @param curveId                    curve id
    /// @param curveAddress               curve contract address
    function setCurve(uint8 curveId, address curveAddress)
        external
        onlyOwner
    {
        config.curves[curveId] = curveAddress;
    }

    /// @notice                           function for storeman submit poly commit
    /// @param groupId                    storeman group id
    /// @param roundIndex                 group negotiate round
    /// @param curveIndex                 singnature curve index
    /// @param polyCommit                 poly commit list (17 order in x0,y0,x1,y1... format)
    function setPolyCommit(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, bytes polyCommit)
        external
    {
        require(polyCommit.length > 0, "Invalid polyCommit");

        GpkTypes.Group storage group = groupMap[groupId];
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        if (group.smNumber == 0) {
            // init group when the first node submit
            GpkLib.initGroup(groupId, group, config, smg);
            round.statusTime = now;
        }
        checkValid(group, roundIndex, curveIndex, GpkTypes.GpkStatus.PolyCommit, address(0), true);
        require(round.srcMap[msg.sender].polyCommit.length == 0, "Duplicate");
        round.srcMap[msg.sender].polyCommit = polyCommit;
        round.polyCommitCount++;
        GpkLib.updateGpk(round, polyCommit);
        GpkLib.updatePkShare(group, round, polyCommit);
        if (round.polyCommitCount >= group.smNumber) {
            round.status = GpkTypes.GpkStatus.Negotiate;
            round.statusTime = now;
        }

        emit SetPolyCommitLogger(groupId, group.round, curveIndex, msg.sender);
    }

    /// @notice                           function for report storeman submit poly commit timeout
    /// @param groupId                    storeman group id
    /// @param curveIndex                 singnature curve index
    function polyCommitTimeout(bytes32 groupId, uint8 curveIndex)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, group.round, curveIndex, GpkTypes.GpkStatus.PolyCommit, address(0), false);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        require(now.sub(round.statusTime) > group.ployCommitPeriod, "Not late"); // round.statusTime had be assigned
        uint slashCount = 0;
        GpkTypes.SlashType[] memory slashTypes = new GpkTypes.SlashType[](group.smNumber);
        address[] memory slashSms = new address[](group.smNumber);
        for (uint i = 0; i < group.smNumber; i++) {
            address src = group.indexMap[i];
            if (round.srcMap[src].polyCommit.length == 0) {
                GpkLib.slash(group, curveIndex, GpkTypes.SlashType.PolyCommitTimeout, src, address(0), true, false, smg);
                slashTypes[slashCount] = GpkTypes.SlashType.PolyCommitTimeout;
                slashSms[slashCount] = src;
                slashCount++;
            }
        }
        GpkLib.slashMulti(group, slashCount, slashTypes, slashSms, smg);
    }

    /// @notice                           function for src storeman submit encSij
    /// @param groupId                    storeman group id
    /// @param roundIndex                 group negotiate round
    /// @param curveIndex                 singnature curve index
    /// @param dest                       dest storeman address
    /// @param encSij                     encSij
    function setEncSij(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, address dest, bytes encSij)
        external
    {
        require(encSij.length > 0, "Invalid encSij");
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, roundIndex, curveIndex, GpkTypes.GpkStatus.Negotiate, dest, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Dest storage d = round.srcMap[msg.sender].destMap[dest];
        require(d.encSij.length == 0, "Duplicate");
        d.encSij = encSij;
        d.setTime = now;
        emit SetEncSijLogger(groupId, group.round, curveIndex, msg.sender, dest);
    }

    /// @notice                           function for dest storeman set check status for encSij
    /// @param groupId                    storeman group id
    /// @param roundIndex                 group negotiate round
    /// @param curveIndex                 singnature curve index
    /// @param src                        src storeman address
    /// @param isValid                    whether encSij is valid
    function setCheckStatus(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, address src, bool isValid)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, roundIndex, curveIndex, GpkTypes.GpkStatus.Negotiate, src, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Src storage s = round.srcMap[src];
        GpkTypes.Dest storage d = s.destMap[msg.sender];
        require(d.encSij.length != 0, "Not ready");
        require(d.checkStatus == GpkTypes.CheckStatus.Init, "Duplicate");

        d.checkTime = now;
        emit SetCheckStatusLogger(groupId, group.round, curveIndex, src, msg.sender, isValid);

        if (isValid) {
            d.checkStatus = GpkTypes.CheckStatus.Valid;
            round.checkValidCount++;
            if (round.checkValidCount >= group.smNumber ** 2) {
                round.status = GpkTypes.GpkStatus.Complete;
                round.statusTime = now;
                GpkLib.tryComplete(group, smg);
            }
        } else {
            d.checkStatus = GpkTypes.CheckStatus.Invalid;
        }
    }

    /// @notice                           function for report src storeman submit encSij timeout
    /// @param groupId                    storeman group id
    /// @param curveIndex                 singnature curve index
    /// @param src                        src storeman address
    function encSijTimeout(bytes32 groupId, uint8 curveIndex, address src)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, group.round, curveIndex, GpkTypes.GpkStatus.Negotiate, src, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Dest storage d = round.srcMap[src].destMap[msg.sender];
        require(d.encSij.length == 0, "Outdated");
        require(now.sub(round.statusTime) > group.defaultPeriod, "Not late");
        GpkLib.slash(group, curveIndex, GpkTypes.SlashType.EncSijTimout, src, msg.sender, true, true, smg);
    }

    /// @notice                           function for src storeman reveal sij
    /// @param groupId                    storeman group id
    /// @param roundIndex                 group negotiate round
    /// @param curveIndex                 singnature curve index
    /// @param dest                       dest storeman address
    /// @param sij                        sij
    /// @param ephemPrivateKey            ecies ephemPrivateKey
    function revealSij(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, address dest, uint sij, uint ephemPrivateKey)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, roundIndex, curveIndex, GpkTypes.GpkStatus.Negotiate, dest, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Src storage src = round.srcMap[msg.sender];
        GpkTypes.Dest storage d = src.destMap[dest];
        require(d.checkStatus == GpkTypes.CheckStatus.Invalid, "Checked Valid");
        d.sij = sij;
        d.ephemPrivateKey = ephemPrivateKey;
        emit RevealSijLogger(groupId, group.round, curveIndex, msg.sender, dest);
        if (GpkLib.verifySij(d, group.addressMap[dest], src.polyCommit, round.curve)) {
          GpkLib.slash(group, curveIndex, GpkTypes.SlashType.CheckInvalid, msg.sender, dest, false, true, smg);
        } else {
          GpkLib.slash(group, curveIndex, GpkTypes.SlashType.EncSijInvalid, msg.sender, dest, true, true, smg);
        }
    }

    /// @notice                           function for report dest storeman check encSij timeout
    /// @param groupId                    storeman group id
    /// @param curveIndex                 singnature curve index
    /// @param dest                       dest storeman address
    function checkEncSijTimeout(bytes32 groupId, uint8 curveIndex, address dest)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, group.round, curveIndex, GpkTypes.GpkStatus.Negotiate, dest, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Dest storage d = round.srcMap[msg.sender].destMap[dest];
        require(d.checkStatus == GpkTypes.CheckStatus.Init, "Checked");
        require(d.encSij.length != 0, "Not ready");
        require(now.sub(d.setTime) > group.defaultPeriod, "Not late");
        GpkLib.slash(group, curveIndex, GpkTypes.SlashType.CheckTimeout, msg.sender, dest, false, true, smg);
    }

    /// @notice                           function for report srcPk submit sij timeout
    /// @param groupId                    storeman group id
    /// @param curveIndex                 singnature curve index
    /// @param src                        src storeman address
    function SijTimeout(bytes32 groupId, uint8 curveIndex, address src)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, group.round, curveIndex, GpkTypes.GpkStatus.Negotiate, src, true);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        GpkTypes.Dest storage d = round.srcMap[src].destMap[msg.sender];
        require(d.checkStatus == GpkTypes.CheckStatus.Invalid, "Not need");
        require(now.sub(d.checkTime) > group.defaultPeriod, "Not late");
        GpkLib.slash(group, curveIndex, GpkTypes.SlashType.SijTimeout, src, msg.sender, true, true, smg);
    }

    /// @notice                           function for terminate protocol
    /// @param groupId                    storeman group id
    /// @param curveIndex                 singnature curve index
    function terminate(bytes32 groupId, uint8 curveIndex)
        external
    {
        GpkTypes.Group storage group = groupMap[groupId];
        checkValid(group, group.round, curveIndex, GpkTypes.GpkStatus.Negotiate, address(0), false);
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        uint slashCount = 0;
        GpkTypes.SlashType[] memory slashTypes = new GpkTypes.SlashType[](group.smNumber * 2);
        address[] memory slashSms = new address[](group.smNumber * 2);
        require(now.sub(round.statusTime) > group.negotiatePeriod, "Not late");

        for (uint i = 0; i < group.smNumber; i++) {
            address src = group.indexMap[i];
            for (uint j = 0; j < group.smNumber; j++) {
                address dest = group.indexMap[j];
                GpkTypes.Dest storage d = round.srcMap[src].destMap[dest];
                if (d.checkStatus == GpkTypes.CheckStatus.Valid) {
                    continue;
                }
                GpkTypes.SlashType sType;
                GpkTypes.SlashType dType;
                if (d.encSij.length == 0) {
                    sType = GpkTypes.SlashType.EncSijTimout;
                    dType = GpkTypes.SlashType.Connive;
                } else if (d.checkStatus == GpkTypes.CheckStatus.Init) {
                    sType = GpkTypes.SlashType.Connive;
                    dType = GpkTypes.SlashType.CheckTimeout;
                } else if (d.checkStatus == GpkTypes.CheckStatus.Invalid) {
                    sType = GpkTypes.SlashType.SijTimeout;
                    dType = GpkTypes.SlashType.Connive;
                }
                GpkLib.slash(group, curveIndex, sType, src, dest, true, false, smg);
                GpkLib.slash(group, curveIndex, dType, src, dest, false, false, smg);
                slashTypes[slashCount] = sType;
                slashSms[slashCount] = src;
                slashCount++;
                slashTypes[slashCount] = dType;
                slashSms[slashCount] = dest;
                slashCount++;
            }
        }
        GpkLib.slashMulti(group, slashCount, slashTypes, slashSms, smg);
    }

    /// @notice                           function for check paras
    /// @param group                      group
    /// @param roundIndex                 group negotiate round
    /// @param curveIndex                 singnature curve index
    /// @param status                     check group status
    /// @param storeman                   check storeman address if not address(0)
    /// @param checkSender                whether check msg.sender
    function checkValid(GpkTypes.Group storage group, uint8 roundIndex, uint8 curveIndex, GpkTypes.GpkStatus status, address storeman, bool checkSender)
        internal
        view
    {
        require(roundIndex == group.round, "Outdated");
        require(curveIndex < group.curveTypes, "Invalid curve");
        GpkTypes.Round storage round = group.roundMap[group.round][curveIndex];
        require(round.status == status, "Invalid status");
        if (storeman != address(0)) {
            require(group.addressMap[storeman].length > 0, "Invalid storeman");
        }
        if (checkSender) {
            require(group.addressMap[msg.sender].length > 0, "Invalid sender");
        }
    }

    function getGroupInfo(bytes32 groupId, int8 roundIndex)
        external
        view
        returns(uint8 queriedRound, uint8 curve1Status, uint curve1StatusTime, uint8 curve2Status, uint curve2StatusTime,
                uint32 ployCommitPeriod, uint32 defaultPeriod, uint32 negotiatePeriod)
    {
        GpkTypes.Group storage group = groupMap[groupId];
        uint8 queryRound = (roundIndex >= 0)? uint8(roundIndex) : group.round;
        GpkTypes.Round storage round1 = group.roundMap[queryRound][0];
        GpkTypes.Round storage round2 = group.roundMap[queryRound][1];
        return (queryRound, uint8(round1.status), round1.statusTime, uint8(round2.status), round2.statusTime,
                group.ployCommitPeriod, group.defaultPeriod, group.negotiatePeriod);
    }

    function getPolyCommit(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, address src)
        external
        view
        returns(bytes polyCommit)
    {
        GpkTypes.Group storage group = groupMap[groupId];
        GpkTypes.Round storage round = group.roundMap[roundIndex][curveIndex];
        return round.srcMap[src].polyCommit;
    }

    function getEncSijInfo(bytes32 groupId, uint8 roundIndex, uint8 curveIndex, address src, address dest)
        external
        view
        returns(bytes encSij, uint8 checkStatus, uint setTime, uint checkTime, uint sij, uint ephemPrivateKey)
    {
        GpkTypes.Group storage group = groupMap[groupId];
        GpkTypes.Round storage round = group.roundMap[roundIndex][curveIndex];
        GpkTypes.Dest storage d = round.srcMap[src].destMap[dest];
        return (d.encSij, uint8(d.checkStatus), d.setTime, d.checkTime, d.sij, d.ephemPrivateKey);
    }

    function getPkShare(bytes32 groupId, uint8 index)
        external
        view
        returns(bytes pkShare1, bytes pkShare2)
    {
        GpkTypes.Group storage group = groupMap[groupId];
        address src = group.indexMap[index];
        mapping(uint8 => GpkTypes.Round) chainRoundMap = groupMap[groupId].roundMap[group.round];
        return (chainRoundMap[0].srcMap[src].pkShare, chainRoundMap[1].srcMap[src].pkShare);
    }

    function getGpk(bytes32 groupId)
        external
        view
        returns(bytes gpk1, bytes gpk2)
    {
        GpkTypes.Group storage group = groupMap[groupId];
        mapping(uint8 => GpkTypes.Round) chainRoundMap = groupMap[groupId].roundMap[group.round];
        return (chainRoundMap[0].gpk, chainRoundMap[1].gpk);
    }

    /// @notice fallback function
    function () public payable {
        revert("Not support");
    }
}