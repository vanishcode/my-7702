import {WebAuthnP256} from "ox";
import {numberToHex, type Address, type Hex} from "viem";

/** abi.encode(WebAuthnAuth) 所需的字段（顺序须与 Solidity 结构体一致）/ fields for the on-chain WebAuthnAuth. */
export interface EncodedWebAuthnAuth {
  authenticatorData: Hex;
  clientDataJSON: string;
  challengeIndex: bigint;
  typeIndex: bigint;
  r: Hex;
  s: Hex;
}

export interface StoredPasskey {
  id: string; // credential id (base64url)
  x: Hex; // 公钥 x / public key x (bytes32)
  y: Hex; // 公钥 y / public key y (bytes32)
}

/** P-256 曲线阶 n / curve order, for low-s normalization. */
const P256_N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;

function storageKey(account: Address) {
  return `my7702.passkey.${account.toLowerCase()}`;
}

export function loadPasskey(account: Address): StoredPasskey | null {
  const v = localStorage.getItem(storageKey(account));
  if (!v) return null;
  try {
    return JSON.parse(v) as StoredPasskey;
  } catch {
    return null;
  }
}

export function savePasskey(account: Address, p: StoredPasskey) {
  localStorage.setItem(storageKey(account), JSON.stringify(p));
}

/** 创建一个真实设备 passkey（Touch ID / Windows Hello / 安全密钥），返回 P-256 公钥坐标。 */
export async function createPasskey(account: Address, label: string): Promise<StoredPasskey> {
  const cred = await WebAuthnP256.createCredential({name: label});
  const stored: StoredPasskey = {
    id: cred.id,
    x: numberToHex(cred.publicKey.x, {size: 32}),
    y: numberToHex(cred.publicKey.y, {size: 32}),
  };
  savePasskey(account, stored);
  return stored;
}

/**
 * 用 passkey 对 challenge(=execHash) 做 WebAuthn 断言，输出链上可解码的 WebAuthnAuth。
 * P256 预编译强制 low-s，这里把 s 归一到 <= n/2。
 */
export async function signPasskey(challenge: Hex, credentialId: string): Promise<EncodedWebAuthnAuth> {
  const {metadata, signature} = await WebAuthnP256.sign({challenge, credentialId});
  let s = signature.s;
  if (s > P256_N / 2n) s = P256_N - s; // 归一 low-s / normalize to low-s
  return {
    authenticatorData: metadata.authenticatorData,
    clientDataJSON: metadata.clientDataJSON,
    challengeIndex: BigInt(metadata.challengeIndex),
    typeIndex: BigInt(metadata.typeIndex),
    r: numberToHex(signature.r, {size: 32}),
    s: numberToHex(s, {size: 32}),
  };
}
