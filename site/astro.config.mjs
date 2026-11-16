// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

const repo = 'https://github.com/Tseku210/khuur_sheet_music';

export default defineConfig({
  site: 'https://tseku210.github.io',
  base: '/khuur_sheet_music',
  integrations: [
    starlight({
      title: 'khuur_sheet_music',
      description:
        'Sheet music for Flutter: a scrolling sheet, edits by tap, and MIDI playback.',
      social: [{ icon: 'github', label: 'GitHub', href: repo }],
      editLink: { baseUrl: `${repo}/edit/main/site/` },
      lastUpdated: true,
      plugins: [starlightLinksValidator()],
      sidebar: [
        { label: 'Tutorial', items: [{ autogenerate: { directory: 'tutorial' } }] },
        { label: 'How-to guides', items: [{ autogenerate: { directory: 'guides' } }] },
        { label: 'Explanation', items: [{ autogenerate: { directory: 'explanation' } }] },
        { label: 'Reference', items: [{ autogenerate: { directory: 'reference' } }] },
      ],
    }),
  ],
});
