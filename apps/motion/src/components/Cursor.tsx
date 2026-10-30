// The pointer: a white arrow with a dark outline; a click presses it and leaves a gold ring.
import { C } from "../theme";

export const Cursor: React.FC<{ x: number; y: number; click: number; opacity?: number; scale?: number }> = ({ x, y, click, opacity = 1, scale = 1 }) => {
  const press = click > 0 && click < 0.35 ? 1 - Math.sin((click / 0.35) * Math.PI) * 0.18 : 1;
  const ring = click > 0 ? click : 0;
  return (
    <>
      {ring > 0 && (
        <div
          style={{
            position: "absolute",
            left: x - 8 - ring * 34,
            top: y - 8 - ring * 34,
            width: 16 + ring * 68,
            height: 16 + ring * 68,
            borderRadius: "50%",
            border: `2px solid ${C.goldLight}`,
            opacity: (1 - ring) * 0.9,
            boxShadow: `0 0 24px rgba(234,214,166,${0.5 * (1 - ring)})`,
          }}
        />
      )}
      <svg
        width={30 * scale}
        height={30 * scale}
        viewBox="0 0 24 24"
        style={{ position: "absolute", left: x - 3 * scale, top: y - 2 * scale, opacity, transform: `scale(${press})`, transformOrigin: "3px 2px", filter: "drop-shadow(0 6px 10px rgba(0,0,0,0.6))" }}
      >
        <path d="M3 2 L3 19 L7.6 14.8 L10.6 21.4 L13.4 20.2 L10.4 13.7 L16.6 13.6 Z" fill="#FFFFFF" stroke="#0A0B0E" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </>
  );
};
