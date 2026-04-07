export const metadata = {
  title: "Enshrined VRF Demo",
  description: "Protocol-native verifiable randomness for the OP Stack",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: "#0a0a0a", color: "#e0e0e0" }}>
        {children}
      </body>
    </html>
  );
}
