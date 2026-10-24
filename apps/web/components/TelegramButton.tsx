/** Bouton « Rejoindre notre groupe Telegram » (lien fourni par les réglages). */
export function TelegramButton({ url, ghost = false }: { url: string; ghost?: boolean }) {
  return (
    <a className={`btn${ghost ? " ghost" : ""}`} href={url} target="_blank" rel="noopener noreferrer">
      <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path fill="currentColor" d="M21.9 4.3 18.7 19.4c-.2 1-.9 1.3-1.8.8l-4.9-3.6-2.4 2.3c-.3.3-.5.5-1 .5l.3-5 9.1-8.2c.4-.4-.1-.6-.6-.2L6.2 13.1l-4.8-1.5c-1-.3-1-1 .2-1.5L20.5 2.8c.9-.3 1.6.2 1.4 1.5Z" />
      </svg>
      Rejoindre notre groupe Telegram
    </a>
  );
}
