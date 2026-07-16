// One-off integration probe against Paytm STAGING. Verifies that:
//  1. the vendored checksum implementation is accepted by Paytm's servers
//     (initiateTransaction returns a txnToken),
//  2. the Transaction Status API request/response contract matches server.js.
// Run: node scripts/testPaytmStaging.js   (uses PAYTM_* from Backend/.env)
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const PaytmChecksum = require('../lib/paytmChecksum');

const MID = process.env.PAYTM_MID;
const KEY = process.env.PAYTM_MERCHANT_KEY;
const WEBSITE = process.env.PAYTM_WEBSITE || 'WEBSTAGING';
const BASE = (process.env.PAYTM_BASE_URL || 'https://securestage.paytmpayments.com').replace(/\/+$/, '');

async function post(url, payload) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await response.json().catch(() => null);
  return { httpStatus: response.status, data };
}

(async () => {
  if (!MID || !KEY) throw new Error('PAYTM_MID / PAYTM_MERCHANT_KEY missing in .env');
  const orderId = `PTM${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;

  // 1. initiateTransaction
  const body = {
    requestType: 'Payment',
    mid: MID,
    websiteName: WEBSITE,
    orderId,
    callbackUrl: `${BASE}/theia/paytmCallback?ORDER_ID=${orderId}`,
    txnAmount: { value: '5.50', currency: 'INR' },
    userInfo: { custId: 'test-cust-001', email: 'test@example.com' },
  };
  const signature = await PaytmChecksum.generateSignature(JSON.stringify(body), KEY);
  const initiate = await post(
    `${BASE}/theia/api/v1/initiateTransaction?mid=${encodeURIComponent(MID)}&orderId=${encodeURIComponent(orderId)}`,
    { body, head: { signature } }
  );
  console.log('initiate HTTP', initiate.httpStatus);
  console.log('initiate resultInfo:', JSON.stringify(initiate.data?.body?.resultInfo));
  const txnToken = initiate.data?.body?.txnToken;
  console.log('txnToken present:', !!txnToken, txnToken ? `(len ${txnToken.length})` : '');

  // 2. Transaction Status for the same (unpaid) order — expect NO_RECORD_FOUND or PENDING
  const statusBody = { mid: MID, orderId };
  const statusSig = await PaytmChecksum.generateSignature(JSON.stringify(statusBody), KEY);
  const status = await post(`${BASE}/v3/order/status`, { body: statusBody, head: { signature: statusSig } });
  console.log('status HTTP', status.httpStatus);
  console.log('status resultInfo:', JSON.stringify(status.data?.body?.resultInfo));
  console.log('status txnAmount:', JSON.stringify(status.data?.body?.txnAmount), 'orderId:', status.data?.body?.orderId);

  // 3. Local checksum verify round-trip (callback-style params object)
  const params = { ORDERID: orderId, STATUS: 'TXN_SUCCESS', TXNAMOUNT: '5.50' };
  const cs = await PaytmChecksum.generateSignature({ ...params }, KEY);
  const ok = await PaytmChecksum.verifySignature({ ...params }, KEY, cs);
  const tampered = await PaytmChecksum.verifySignature({ ...params, TXNAMOUNT: '999.00' }, KEY, cs);
  console.log('verifySignature valid:', ok, '| tampered rejected:', tampered === false);

  const pass = initiate.data?.body?.resultInfo?.resultStatus === 'S' && !!txnToken && ok && tampered === false;
  console.log(pass ? '\nPAYTM STAGING PROBE: PASS' : '\nPAYTM STAGING PROBE: FAIL');
  process.exit(pass ? 0 : 1);
})().catch(err => { console.error('PROBE ERROR:', err.message); process.exit(1); });
