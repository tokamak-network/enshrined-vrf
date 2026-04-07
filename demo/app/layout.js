export const metadata = {
  title: "Enshrined VRF Demo",
  description: "Protocol-native verifiable randomness for the OP Stack",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: "#ffffff", color: "#1a1a1a" }}>
        {children}
      </body>
    </html>
  );
}
