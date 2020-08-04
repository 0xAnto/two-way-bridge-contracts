const StoremanGroupProxy = artifacts.require('StoremanGroupProxy');
const StoremanGroupDelegate = artifacts.require('StoremanGroupDelegate');
const { registerStart, stakeInPre, toSelect } = require('../base.js')

contract('open_storeman_it', async () => {
  before("start smg", async() => {
    let smgProxy = await StoremanGroupProxy.deployed();
    let smgSc = await StoremanGroupDelegate.at(smgProxy.address);
    console.log("smg contract address: %s", smgProxy.address);

    let groupId = await registerStart(smgSc);
    await stakeInPre(smgSc, groupId);
    // await toSelect(smgSc, groupId);
  })

  it('it_stub', async () => {
  })
})