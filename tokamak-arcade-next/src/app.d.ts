declare global {
  namespace App {}

  interface Window {
    ethereum?: import('viem').EIP1193Provider;
  }
}

export {};
