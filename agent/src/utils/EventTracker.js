const wanchain = require('./wanchain');
const tool = require('./tools');

class EventTracker {
  constructor(id, startBlock, cb, interval = 1 /* 1-10 minute */) {
    // context
    this.id = id;
    this.contextName = id + '_eventTracker.cxt';
    let cxt = tool.readContext(this.contextName);
    if (cxt && cxt.startBlock > startBlock) {
      startBlock = cxt.startBlock;
    }
    this.lastBlock = startBlock - 1;
    this.cb = cb;
    interval = (interval > 10) ? 10 : interval;
    this.schInterval = interval * 60 * 1000;
    this.schThreshold = interval * 6;
    this.schBatchSize = interval * 360; // half an hour
    this.toStop = false;
    // name => {address, topics} 
    this.subscribeMap = new Map();
    this.subscribeArray = [];
    this.eventList = [];
  }

  subscribe(name, scAddress, topics) {
    this.subscribeMap.set(name, {address: scAddress, topics: topics});
    this.subscribeArray = Array.from(this.subscribeMap);
  }

  start() {
    this.next(this.schThreshold + 1);
  }

  stop() {
    this.toStop = true;
  }

  async mainLoop() {
    let eventArray = [];
    try {
      let latestBlock = await wanchain.getBlockNumber();
      let startBlock = this.lastBlock + 1;
      let endBlock = startBlock + this.schBatchSize - 1; // 100 blocks total
      if (endBlock > latestBlock) {
        endBlock = latestBlock;
      }
      console.log("%s eventTracker scan block %d-%d", this.id, startBlock, endBlock);
      await Promise.all(this.subscribeArray.map(sub => {
        return new Promise((resolve, reject) => {
          wanchain.getEvents({
            address: sub[1].address,
            topics: sub[1].topics,
            fromBlock: startBlock,
            toBlock: endBlock
          }).then((events) => {
            events.forEach((evt) => {
              evt.name = sub[0];
              eventArray.push(evt);              
            })
            resolve();
          }).catch((err) => {
            console.error("%s eventTracker fetch event %s from block %d-%d error: %O", this.id, sub[0], startBlock, endBlock, err);
            reject(err);
          })
        });
      }));
      this.lastBlock = endBlock;
      if (eventArray.length) {
        // console.log("%s eventTracker fetched %d event from block %d-%d", this.id, eventArray.length, startBlock, endBlock);
        eventArray.sort(this.sortLog);
        this.eventList = this.eventList.concat(eventArray);
      }

      await this.dispatch();

      let nextBlock = this.eventList.length? this.eventList[0].blockNumber : endBlock + 1;
      tool.writeContext(this.contextName, {startBlock: nextBlock});
      this.next(latestBlock - endBlock);
    } catch (err) {
      console.error("%s evevtTracker loop error: %O", this.id, err);
      this.next();
    }
  }

  async dispatch() {
    if (this.eventList.length == 0) {
      // console.log("dispatchEvent finished");
      return;
    }
    let success = await this.cb(this.eventList[0]);
    if (success) {
      this.eventList.splice(0, 1);
      await this.dispatch();
    } else {
      console.log("dispatch event error: %O", this.eventList[0]);
      return;
    }
  }

  next(blockLeft = 0) {
    if (this.toStop) {
      return;
    }
    let interval = this.schInterval;
    if (blockLeft > this.schThreshold) {
      interval /= 60;
    }
    setTimeout(() => {
      this.mainLoop();
    }, interval);
  }

  sortLog(a, b) {
    if (a.blockNumber != a.blockNumber) {
      return (a.blockNumber - b.blockNumber);
    }
    if (a.transactionIndex != a.transactionIndex) {
      return (a.transactionIndex - b.transactionIndex);
    }
    return (a.logIndex - b.logIndex);
  }
}

module.exports = EventTracker;