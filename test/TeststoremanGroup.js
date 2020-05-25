const utils = require("./utils");
const Web3 = require('web3')
const net = require('net')
const ethutil = require("ethereumjs-util");
const pu = require('promisefy-util')
const schnorr = require('../utils/schnorr/tools.js');

const TestSmg = artifacts.require('TestSmg')
const TokenManagerProxy = artifacts.require('TokenManagerProxy');
const TokenManagerDelegate = artifacts.require('TokenManagerDelegate');
const StoremanGroupDelegate = artifacts.require('StoremanGroupDelegate')
const StoremanGroupProxy = artifacts.require('StoremanGroupProxy');
const HTLCProxy = artifacts.require('HTLCProxy');
const HTLCDelegate = artifacts.require('HTLCDelegate');
const CreateGpkProxy = artifacts.require('CreateGpkProxy');
const PreCompile = artifacts.require('Enhancement');

const wanUtil = require('wanchain-util');
const Tx = wanUtil.wanchainTx;
let contractAddress = undefined //    "0x4553061E7aD83d83F559487B1EB7847a9F90ad59"; //   

//let web3 = new Web3(new Web3.providers.IpcProvider('/home/lzhang/.wanchain/pluto/gwan.ipc',net))
let web3 = new Web3(new Web3.providers.HttpProvider('http://192.168.1.179:7654'))
let gGasLimit=9000000;
let gGasPrice=200000000000;

/*************************************
staker: 1000 ~ 1000+100
delegator: stakerId*100 ~ stakerID*100+1000
 ****************************************/



let EOS = utils.stringTobytes("EOS")



contract('TestSmg', async (accounts) => {
    let tester = accounts[0]
    let id = utils.stringTobytes32(Date.now().toString())
    let gaddr = '0xf223ebd621fc35417023fdc52d3cc55de672e6de'
    //let gpk = '0x047793ef5f8e57e872ea9fbb18bd710ab96ea4f646134d3308930cbf62e73f0e1c8d5b3b793573090fa4a7e7e5c38fd987e889bc3e720e05b243e856f632ae7cc5'
    let gpk = '0x04a4a90e6b3914780a66e3d34134478ffe455b657705d9c71bf48f66b52e486ed8362d850558f152ff03a5210a63625438cbaa9cb924bd90d597299cf9c3bcbe70';
    let skSmg ='0x000000000000000000000000000000000000000000000000000000000000270f'


    const memberCountDesign = 4
    const threshold  = 3
    let smgProxy
    let  smg

    before("init contracts", async() => {
        if(!contractAddress) {
            smgProxy = await StoremanGroupProxy.deployed();

            smg = await StoremanGroupDelegate.at(smgProxy.address)
            contractAddress = smgProxy.address
            console.log("==============================storemanGroup smgProxy contractAddress: ", contractAddress)
        }

        let gpkProxy = await CreateGpkProxy.deployed();
        console.log("CreateGpk contractAddress: %s", gpkProxy.address);

        let preCompile = await PreCompile.deployed();
        console.log("PreCompile contractAddress: %s", preCompile.address);
    
        tsmg = await TestSmg.deployed();
        await tsmg.setSmgAddr(smgProxy.address)

        let tmProxy = await TokenManagerProxy.deployed();
        let tm = await TokenManagerDelegate.at(tmProxy.address);

        //await smg.setDependence(tmProxy.address, tmProxy.address);

        await tm.addToken(EOS, 10000,'0x99999999',60 * 60 * 72,EOS,EOS,8)
        let t = await tm.getTokenInfo(EOS)
        console.log("tokens:", t)

    })



    it('registerStart_1 ', async ()=>{
        let count = 4;
        let wks = []
        let srs= []
        for(let i=0; i<count;i++){
            let {addr:sr} = utils.getAddressFromInt(i+1000)
            let {addr:wk} = utils.getAddressFromInt(i+2000)
            wks.push(wk)
            srs.push(sr)
        }
        let tx = await smg.registerStart(id,memberCountDesign,threshold,12345, 90, 14,33,utils.stringTobytes32(""), utils.stringTobytes("EOS"),wks,srs,
            {from: tester})
        console.log("tx:", tx)
        console.log("group:",await smg.groups(id))
    })
    it('test stakeIn', async()=>{
        let stakerCount = 7
        for(let i=0; i<stakerCount; i++){
            let sf = utils.getAddressFromInt(i+1000)
            let sw = utils.getAddressFromInt(i+2000)
            let en = utils.getAddressFromInt(i+3000)
            let sdata =  smg.contract.methods.stakeIn(id, sw.pk,en.pk,2000+i).encodeABI()
            console.log("sdata:",sdata)
            let rawTx = {
                Txtype: 0x01,
                nonce:  await pu.promisefy(web3.eth.getTransactionCount,[sf.addr,"pending"], web3.eth),
                gasPrice: gGasPrice,
                gas: gGasLimit,
                to: contractAddress,
                chainId: 6,
                value: i+2000,
                data: sdata,
            }
            //console.log("rawTx:", rawTx)
            let tx = new Tx(rawTx)
            tx.sign(sf.priv)
            const serializedTx = '0x'+tx.serialize().toString('hex');
            console.log("serializedTx:",serializedTx)
            //let txhash = await web3.eth.sendSignedTransaction(serializedTx)
            let txhash = await pu.promisefy(web3.eth.sendSignedTransaction,[serializedTx],web3.eth);
            await utils.waitReceipt(txhash)
            console.log("txhash i:", i, txhash)


            let deCount=0;
            for(let j=0; j<deCount; j++){
                let de = utils.getAddressFromInt((i+1000)*10*1000 + j)
                let dedata = smg.contract.methods.addDelegator(id,sw.addr).encodeABI()
                let rawTx = {
                    Txtype: 0x01,
                    nonce: await pu.promisefy(web3.eth.getTransactionCount,[de.addr,"pending"], web3.eth),
                    gasPrice: gGasPrice,
                    gasLimit: gGasLimit,
                    to: contractAddress,
                    chainId: 6,
                    value: j+10000,
                    data: dedata,
                }
                console.log("rawTx j:", j, rawTx)

                let tx = new Tx(rawTx)
                tx.sign(de.priv)
                const serializedTx = '0x'+tx.serialize().toString('hex');
                txhash = await pu.promisefy(web3.eth.sendSignedTransaction,[serializedTx],web3.eth)
                console.log("txhash i j:", i,j, txhash)
            }

            let candidate = undefined;
            while(!(candidate && candidate["2"] == deCount)){
                console.log("candicate i", i, candidate)
                await pu.sleep(3000)
                candidate  = await smg.getStaker(id, sw.addr)
            }
        }


    })

    it('test toSelect', async ()=>{
        let tx = await smg.toSelect(id,{from: tester})
        console.log("toSelect tx:", tx)
        await utils.waitReceipt(tx.tx)
        console.log("group:",await smg.groups(id))

        
        let count = await smg.getSelectedSmNumber(id)
        console.log("count :", count)

        for(let i=0; i<count; i++) {
            let skAddr = await smg.getSelectedSmInfo(id, i)
            console.log("skAddr:", i,skAddr)
            // let sk = await smg.getSmInfo(id, skAddr[0]);
            // console.log("sk, i:", i, sk)
        }

    })
    it('setGpk', async() => {
       let tx =  await smg.setGpk(id, gpk)
       console.log("setGpk tx:", tx)
    })

    it('inSmgLock', async()=>{
        let typesArray = ['bytes','bytes32','address','uint'];
        let xhash = utils.stringTobytes32("xhash")
        let waddr =  utils.getAddressFromInt(3).addr
        let value = 100;
        let parameters = [EOS, xhash,waddr, value];
    
   
        let s = schnorr.getS(skSmg, typesArray, parameters);
        console.log("=====s===hex:", s);
        let r = schnorr.getR()
        console.log("=====R===hex:",r);

        let htlcProxy = await HTLCProxy.deployed();
        let htlc = await HTLCDelegate.at(htlcProxy.address);
        console.log("htlcProxy.address:", htlcProxy.address)

        let locktx = await htlc.inSmgLock(EOS, xhash, waddr, 100, gpk, r,s)   
        console.log("locktx:", locktx); 
    })


})
