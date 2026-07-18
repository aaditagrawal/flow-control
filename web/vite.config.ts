import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  // Relative assets work from GitHub Pages project sites and equivalent static hosts.
  base: './',
  plugins: [react()],
})
