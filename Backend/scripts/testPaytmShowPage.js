// Probe: mint a fresh txnToken, then POST the showPaymentPage form exactly as
// the SDK webview does, against both candidate hosts, and report what each
// cashier endpoint returns (HTTP status + first bytes of body).
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const PaytmChecksum = require('../lib/paytmChecksum');

const MID = process.env.PAYTM_MID;
const KEY = process.env.PAYTM_MERCHANT_KEY;
const WEBSITE = process.env.PAYTM_WEBSITE || 'WEBSTAGING';
const NEW_BASE = 'https://securestage.paytmpayments.com';
const LEGACY_BASE = 'https://securegw-stage.paytm.in';

async function mintToken(orderId) {
  const body = {
    requestType: 'Payment',
    mid: MID,
    websiteName: WEBSITE,
    orderId,
    callbackUrl: `${NEW_BASE}/theia/paytmCallback?ORDER_ID=${orderId}`,
    txnAmount: { value: '5.50', currency: 'INR' },
    userInfo: { custId: 'test-cust-001' },
  };
  const signature = await PaytmChecksum.generateSignature(JSON.stringify(body), KEY);
  const res = await fetch(
    `${NEW_BASE}/theia/api/v1/initiateTransaction?mid=${MID}&orderId=${orderId}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ body, head: { signature } }) }
  );
  const data = await res.json();
  return { txnToken: data?.body?.txnToken, resultInfo: data?.body?.resultInfo };
}

async function postShowPage(base, orderId, txnToken, withQuery) {
  const url = withQuery
    ? `${base}/theia/api/v1/showPaymentPage?mid=${encodeURIComponent(MID)}&orderId=${encodeURIComponent(orderId)}`
    : `${base}/theia/api/v1/showPaymentPage`;
  const form = new URLSearchParams({ mid: MID, orderId, txnToken });
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
      redirect: 'manual',
    });
    const text = await res.text();
    const snippet = text.replace(/\s+/g, ' ').slice(0, 160);
    console.log(`\n[${withQuery ? 'query' : 'plain'}] ${url}`);
    console.log(`  HTTP ${res.status} ${res.headers.get('location') || ''}`);
    console.log(`  body: ${snippet}`);
  } catch (e) {
    console.log(`\n[${withQuery ? 'query' : 'plain'}] ${url}\n  ERROR: ${e.message}`);
  }
}

(async () => {
  const orderId = `PTM${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;
  const { txnToken, resultInfo } = await mintToken(orderId);
  console.log('mint:', JSON.stringify(resultInfo), 'token:', !!txnToken);
  if (!txnToken) process.exit(1);

  await postShowPage(NEW_BASE, orderId, txnToken, true);
  await postShowPage(NEW_BASE, orderId, txnToken, false);
  await postShowPage(LEGACY_BASE, orderId, txnToken, true);
})().catch(e => { console.error('PROBE ERROR:', e.message); process.exit(1); });
