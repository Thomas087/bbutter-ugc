---
name: Clinical Purity
colors:
  surface: '#fcf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fcf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f0eded'
  surface-container-high: '#eae7e7'
  surface-container-highest: '#e5e2e1'
  on-surface: '#1c1b1b'
  on-surface-variant: '#454654'
  inverse-surface: '#313030'
  inverse-on-surface: '#f3f0ef'
  outline: '#757686'
  outline-variant: '#c5c5d7'
  surface-tint: '#3d4ed5'
  primary: '#000d74'
  on-primary: '#ffffff'
  primary-container: '#0019af'
  on-primary-container: '#8b98ff'
  inverse-primary: '#bcc2ff'
  secondary: '#5d5f5f'
  on-secondary: '#ffffff'
  secondary-container: '#dfe0e0'
  on-secondary-container: '#616363'
  tertiary: '#1c2134'
  on-tertiary: '#ffffff'
  tertiary-container: '#31364b'
  on-tertiary-container: '#9a9fb8'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dfe0ff'
  primary-fixed-dim: '#bcc2ff'
  on-primary-fixed: '#000a64'
  on-primary-fixed-variant: '#2032bd'
  secondary-fixed: '#e2e2e2'
  secondary-fixed-dim: '#c6c6c7'
  on-secondary-fixed: '#1a1c1c'
  on-secondary-fixed-variant: '#454747'
  tertiary-fixed: '#dde1fc'
  tertiary-fixed-dim: '#c1c5df'
  on-tertiary-fixed: '#161b2e'
  on-tertiary-fixed-variant: '#41465b'
  background: '#fcf9f8'
  on-background: '#1c1b1b'
  surface-variant: '#e5e2e1'
typography:
  hero:
    fontFamily: manrope
    fontSize: 112px
    fontWeight: '700'
    lineHeight: '1.02'
    letterSpacing: -0.025em
  stat:
    fontFamily: manrope
    fontSize: 200px
    fontWeight: '700'
    lineHeight: '0.92'
    letterSpacing: -0.045em
  title:
    fontFamily: manrope
    fontSize: 84px
    fontWeight: '700'
    lineHeight: '1.08'
    letterSpacing: -0.025em
  body:
    fontFamily: inter
    fontSize: 40px
    fontWeight: '400'
    lineHeight: '1.5'
  badge:
    fontFamily: manrope
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: 0.08em
    textTransform: uppercase
  label:
    fontFamily: inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: '1'
    letterSpacing: 0.18em
    textTransform: uppercase
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  container-max: 1280px
  gutter: 24px
  margin: 32px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 32px
  section-gap: 80px
---

## Brand & Style
The design system is rooted in the intersection of pharmaceutical authority and wellness-focused approachability. It targets a discerning consumer looking for scientific validation without the cold, intimidating atmosphere of traditional medicine. 

The primary design style is **Minimalism** with a **Corporate Modern** structure. It communicates cleanliness and safety, ensuring that every interface element feels intentional and "medical-grade." The inclusion of organic shapes in the background and high-quality photography softens the rigid grid, providing a "gentle" visual layer that mirrors the product’s skin-safe properties. The emotional goal is to establish instant trust and clarity.

## Colors
The palette is dominated by a deep, authoritative Blue (#0019AF), which functions as the primary driver for high-priority actions and brand identity. This blue evokes a sense of medical expertise and reliability. 

The background is a soft, warm Off-White (#F9F9F9), chosen to reduce the harshness of pure white while maintaining a clinical feel. A tertiary light wash of blue is used for secondary surfaces or subtle highlights. Neutral tones are strictly reserved for typography and thin UI borders to maintain a high-contrast, legible environment that focuses on transparency.

## Typography
The system uses a pairing of **Manrope** and **Inter** to balance personality with utility.

Manrope is utilized for headlines to provide a modern, slightly geometric, and refined character. Tight letter spacing is applied to larger headlines to ensure they feel grounded and authoritative. Inter is used for all body copy and labels because of its exceptional legibility and systematic, neutral appearance, which reinforces the scientific and transparent nature of the brand. Hierarchy is strictly enforced through weight changes rather than excessive color variance.

The scale is deliberately reduced to **six sizes only**, calibrated for Instagram slider canvases (1080 × 1350 px) where small sizes must stay legible at scroll distance and reels (the same PNGs are reused as video frames):

- `hero` — 112px Manrope 700 — reserved for the cover slide of a series (one-time opening statement).
- `stat` — 200px Manrope 700, line-height 0.92, letter-spacing −0.045em — the dominant headline number on a "chiffre choc" / data slide. One stat per slide, max. Sub-stats in multi-up grids reuse `title`.
- `title` — 84px Manrope 700 — every other title, quote, or Conclusion headline. Also covers sub-stats in multi-up grids (trimester %, comparatif columns, etc.).
- `body` — 40px Inter 400 — every paragraph, subtitle, or descriptive block. Line-height 1.5, `text-wrap: pretty`.
- `badge` — 28px Manrope 700 uppercase — verdict pills and emphatic micro-labels on a primary-coloured chip. Pills must stay compact, so this tier does not scale with the others.
- `label` — 20px Inter 600 uppercase — all eyebrows, topbars, botbars, and micro-labels are unified at this single size.

No intermediate sizes, no slide-to-slide variation. Any design output (slider, post, print sheet) stays inside this six-step ladder. If a new content shape appears to need another size, update this file rather than patching one slide.

## Elevation & Depth
Depth is conveyed primarily through **Low-contrast outlines** and **Tonal layers**. 

To maintain the medical-grade aesthetic, heavy shadows are avoided. Instead, surfaces are differentiated by subtle shifts between the warm cream background and pure white containers, often separated by a 1px border in a very light grey or a desaturated version of the primary blue. Where depth is required for interactive elements (like a modal or a floating cart), a very soft, highly diffused ambient shadow with a low-opacity blue tint is used to keep the element feeling "light" and clinical.

## Shapes
The shape language is "Rounded" (0.5rem base), striking a balance between the precision of clinical tools (sharp) and the softness of human skin (pill-shaped). 

This mid-level roundedness applies to buttons, input fields, and product cards. To contrast this structured UI, "Organic Blobs" are used as background decorative elements or masks for photography. These organic shapes should be asymmetrical and fluid, softening the overall presentation and making the medical nature of the product feel approachable and "gentle."

## Components
- **Buttons:** Primary buttons use the deep blue background with white text, featuring a 0.5rem corner radius. Secondary buttons use a transparent background with a 1px blue stroke.
- **Input Fields:** Minimalist design with a 1px stroke that thickens slightly on focus. Labels are always positioned outside the field in the `label-sm` style for maximum clarity.
- **Chips / Badges:** Used for product attributes (e.g., "Vegan", "Dermatologically Tested"). These use a soft tint of the primary blue with deep blue text.
- **Product Cards:** Featuring high-resolution photography on a white background with a thin neutral border. Information is stacked using the established vertical rhythm.
- **Icons:** Simple, 2px stroke line-art icons. Icons should be functional and literal (e.g., a simple molecule for "scientific backing") to maintain transparency.
- **Accordions:** Used for FAQs and Ingredient lists, featuring thin horizontal dividers and simple plus/minus toggles to keep the information dense but accessible.