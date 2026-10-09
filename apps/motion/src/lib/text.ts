// French typography: a non-breaking space before « : ; ? ! » and inside guillemets, so that no
// line of a caption or a note starts with a colon.
export const fr = (s: string) => s.replace(/ ([:;?!»])/g, " $1").replace(/« /g, "« ");
