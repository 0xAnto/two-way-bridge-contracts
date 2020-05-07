
function sha256(message) {
  const crypto=require('crypto');
  return crypto.createHash('SHA256').update(message, "utf8").digest('hex');
}

function keccak(message) {
  const keccak = require('keccak');
  return keccak('keccak256').update(message).digest('hex');
}

function newContract(contract, ...args) {
  const deployment = contract.new(...args);
  return new web3.eth.Contract(contract.abi, deployment.address);
}

function newContractAt(contract, address) {
  return new web3.eth.Contract(contract.abi, address);
}

function contractAt(contract, address) {
  return contract.at(address);
}

async function deployContract(contract, ...args) {
  const deployment = await contract.new(...args);
  return contract.at(deployment.address);
}

function linkLibrary(contract, ...args) {
  let isInstance = (args.length === 1);
  if (isInstance) {
    // 0: libInstance
    return contract.link(args[0]);
  }
  // 0: libName, 1: libAddress
  return contract.link(args[0], args[1]);
}

/**
 * {
 *   "libName": libAddress
 * }
 */
function linkMultiLibrary(contract, libs) {
  return contract.link(libs);
}
function stringTobytes32(name){
  let b = Buffer.alloc(32)
  b.write(name, 32-name.length,'ascii')
  let id = '0x'+b.toString('hex')
  console.log("id:",id)
  return id
}


async function waitReceipt(txhash) {
  let lastBlock = await pu.promisefy(web3.eth.getBlockNumber, [], web3.eth)
  let newBlock = lastBlock
  while(newBlock - lastBlock < 10) {
      await pu.sleep(1000)
      newBlock = await pu.promisefy(web3.eth.getBlockNumber, [], web3.eth)
      if( newBlock != lastBlock) {
          let rec = await pu.promisefy(web3.eth.getTransactionReceipt, [txhash], web3.eth)
          if ( rec ) {
              return rec
          }
      }
  }
  assert(false,"no receipt goted in 10 blocks")
  return null
}

module.exports = {
  sha256: sha256,
  keccak: keccak,
  newContract: newContract,
  newContractAt: newContractAt,
  contractAt: contractAt,
  deployContract: deployContract,
  linkLibrary: linkLibrary,
  linkMultiLibrary: linkMultiLibrary,
  stringTobytes32:stringTobytes32,
  waitReceipt:waitReceipt,
};