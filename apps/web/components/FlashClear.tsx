"use client";

import { useEffect } from "react";

/** Efface le message flash une fois affiché (il ne réapparaît pas sur la page suivante). */
export function FlashClear() {
  useEffect(() => {
    document.cookie = "vk_flash=; Max-Age=0; Path=/admin; SameSite=Lax";
  }, []);
  return null;
}
