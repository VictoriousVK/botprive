// The three films (and their captions-free variants), registered for the studio and the renders.
import "./fonts";
import { Composition } from "remotion";
import { FilmComposition } from "./compositions/FilmComposition";
import { FILM } from "./content/film";
import { PROMO } from "./content/promo";
import type { Film } from "./content/types";
import { VERTICAL } from "./content/vertical";
import { place } from "./lib/timeline";

const comp = (id: string, film: Film, captions = true) => (
  <Composition
    key={id}
    id={id}
    component={FilmComposition}
    durationInFrames={place(film).total}
    fps={film.fps}
    width={film.width}
    height={film.height}
    defaultProps={{ film, captions }}
  />
);

export const Root: React.FC = () => (
  <>
    {comp("AlphaEdgeFilm", FILM)}
    {comp("AlphaEdgePromo", PROMO)}
    {comp("AlphaEdgeVertical", VERTICAL)}
    {/* Same films without burnt-in captions (subtitles as SRT, or a voice-over that carries the text). */}
    {comp("AlphaEdgeFilmClean", FILM, false)}
    {comp("AlphaEdgePromoClean", PROMO, false)}
    {comp("AlphaEdgeVerticalClean", VERTICAL, false)}
  </>
);
