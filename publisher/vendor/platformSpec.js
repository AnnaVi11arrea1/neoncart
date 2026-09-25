// GENERATED FILE — do not edit.
//
// Compiled from lib/platformSpec.ts in the everfluorescent-cms repository, which is the
// single source of truth for every platform limit in both halves of the post
// queue. Change it THERE and run `npm run vendor` in publisher/.
//
// Source set hash: 79d156150fd1bc92

/**
 * platformSpec — the single source of truth for what each platform accepts.
 *
 * Both the preview renderer (components/previews/*) and the pre-publish checks
 * (lib/preflight.ts) read from this file, so a preview can never show something
 * the publish gate would allow through, or vice versa. When a platform changes a
 * limit, this is the only file to edit.
 *
 * PROVENANCE — read 2026-09-19:
 *   verified: true  → taken from the platform's own developer documentation, read
 *                     on 2026-09-19 (see `sources` on each platform).
 *   verified: false → carried from general knowledge. Re-read the linked doc and
 *                     flip the flag before anyone relies on it. These are the
 *                     caption and hashtag ceilings and the video duration ranges.
 */
export const RATIOS = {
    square: { label: '1:1', value: 1 },
    portrait45: { label: '4:5', value: 0.8 },
    landscape191: { label: '1.91:1', value: 1.91 },
    vertical169: { label: '9:16', value: 0.5625 },
    landscape169: { label: '16:9', value: 16 / 9 },
};
const IG_SAFE = { top: 8, bottom: 22, left: 4, right: 18 };
const TT_SAFE = { top: 10, bottom: 18, left: 4, right: 22 };
export const PLATFORMS = {
    instagram: {
        id: 'instagram',
        label: 'Instagram',
        accent: '#C13584',
        caption: { max: 2200, recommended: 300, verified: false },
        hashtags: { max: 30, recommended: 8, verified: false },
        linksClickable: false,
        publishPath: 'container-then-publish',
        formats: [
            {
                id: 'feed_image',
                label: 'Feed image',
                ratios: [RATIOS.portrait45, RATIOS.square, RATIOS.landscape191],
                minAssets: 1,
                maxAssets: 1,
                // The publishing API accepts JPEG only for single images — not PNG, and
                // not the extended JPEG formats (MPO, JPS). Verified 2026-09-19.
                imageMimeTypes: ['image/jpeg'],
            },
            {
                id: 'carousel',
                label: 'Carousel',
                ratios: [RATIOS.portrait45, RATIOS.square],
                minAssets: 2,
                maxAssets: 10,
                imageMimeTypes: ['image/jpeg'],
            },
            {
                id: 'reel',
                label: 'Reel',
                ratios: [RATIOS.vertical169],
                minAssets: 1,
                maxAssets: 1,
                duration: { minSeconds: 3, maxSeconds: 90, verified: false },
                safeArea: IG_SAFE,
            },
            {
                id: 'story',
                label: 'Story',
                ratios: [RATIOS.vertical169],
                minAssets: 1,
                maxAssets: 1,
                duration: { minSeconds: 1, maxSeconds: 60, verified: false },
                safeArea: IG_SAFE,
            },
        ],
        workerNotes: [
            'Publishing is two calls: create a media container, then publish it.',
            'Media must sit at a publicly reachable URL at publish time — Meta fetches it itself.',
            'Account must be an Instagram professional account connected to a Page, with Page Publishing Authorization completed.',
            'Capped at 100 API-published posts per rolling 24 hours; a carousel counts as one.',
            'Shopping tags and branded-content tags cannot be set through the API.',
            'Single images must be delivered as JPEG. Request the asset as ?fm=jpg rather than publishing the stored original, which may be PNG, HEIC or AVIF — the store has no format validation, so anything can arrive.',
        ],
        sources: ['https://developers.facebook.com/docs/instagram-platform/content-publishing/'],
    },
    tiktok: {
        id: 'tiktok',
        label: 'TikTok',
        accent: '#00C4C4',
        caption: { max: 2200, recommended: 150, verified: false },
        hashtags: { max: 30, recommended: 5, verified: false },
        linksClickable: false,
        publishPath: 'direct-or-draft',
        formats: [
            {
                id: 'video',
                label: 'Video',
                ratios: [RATIOS.vertical169],
                minAssets: 1,
                maxAssets: 1,
                duration: { minSeconds: 3, maxSeconds: 600, verified: false },
                safeArea: TT_SAFE,
            },
        ],
        workerNotes: [
            'Two modes: Direct Post publishes to the profile; Upload sends a draft to the creator inbox to finish in the TikTok editor.',
            'Until the app passes TikTok audit, posted content is restricted to private / self-only — ship on Upload-to-drafts first.',
            'Query the creator info endpoint before posting so only the privacy options that account allows are offered.',
            'Posting is capped per account per day.',
        ],
        sources: ['https://developers.tiktok.com/products/content-posting-api/'],
    },
    facebook: {
        id: 'facebook',
        label: 'Facebook',
        accent: '#1877F2',
        caption: { max: 63206, recommended: 400, verified: false },
        hashtags: { max: 30, recommended: 3, verified: false },
        linksClickable: true,
        publishPath: 'single-call',
        formats: [
            {
                id: 'feed_image',
                label: 'Photo post',
                ratios: [RATIOS.square, RATIOS.landscape191, RATIOS.portrait45],
                minAssets: 1,
                maxAssets: 1,
            },
            {
                id: 'carousel',
                label: 'Multi-photo post',
                ratios: [RATIOS.square, RATIOS.landscape191],
                minAssets: 2,
                maxAssets: 10,
            },
            {
                id: 'video',
                label: 'Video',
                ratios: [RATIOS.landscape169, RATIOS.vertical169, RATIOS.square],
                minAssets: 1,
                maxAssets: 1,
                duration: { minSeconds: 1, maxSeconds: 1200, verified: false },
            },
            { id: 'link', label: 'Link post', ratios: [RATIOS.landscape191], minAssets: 0, maxAssets: 1 },
            { id: 'text', label: 'Text only', ratios: [], minAssets: 0, maxAssets: 0 },
        ],
        workerNotes: [
            'Posts with a Page access token against the Page feed, photo and video endpoints.',
            'Supports scheduled and unpublished posts, which is the cheapest way to get a native preview.',
            'NOT yet verified against current Meta Pages documentation — confirm before wiring.',
        ],
        sources: [],
    },
    linkedin: {
        id: 'linkedin',
        label: 'LinkedIn',
        accent: '#0A66C2',
        caption: { max: 3000, recommended: 600, verified: false },
        hashtags: { max: 30, recommended: 3, verified: false },
        linksClickable: true,
        publishPath: 'single-call',
        formats: [
            { id: 'text', label: 'Text only', ratios: [], minAssets: 0, maxAssets: 0 },
            {
                id: 'feed_image',
                label: 'Image',
                ratios: [RATIOS.landscape191, RATIOS.square],
                minAssets: 1,
                maxAssets: 1,
            },
            {
                id: 'carousel',
                label: 'Multi-image',
                ratios: [RATIOS.square, RATIOS.landscape191],
                minAssets: 2,
                maxAssets: 20,
            },
            {
                id: 'video',
                label: 'Video',
                ratios: [RATIOS.landscape169, RATIOS.square, RATIOS.vertical169],
                minAssets: 1,
                maxAssets: 1,
                duration: { minSeconds: 3, maxSeconds: 600, verified: false },
            },
            { id: 'link', label: 'Article share', ratios: [RATIOS.landscape191], minAssets: 0, maxAssets: 1 },
        ],
        workerNotes: [
            'POST /rest/posts with a LinkedIn-Version header (YYYYMM) and X-Restli-Protocol-Version 2.0.0.',
            'Author is the organization URN (urn:li:organization:{id}); the authorising member needs an admin role on the page.',
            'Needs the w_organization_social scope.',
            'Images and video upload first to get a urn:li:image / urn:li:video, which the post then references.',
            'The legacy ugcPosts API is being retired — build on Posts.',
        ],
        sources: [
            'https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api',
        ],
    },
};
export const PLATFORM_IDS = Object.keys(PLATFORMS);
export function getPlatform(id) {
    return id ? PLATFORMS[id] : undefined;
}
export function getFormat(platformId, formatId) {
    const platform = getPlatform(platformId);
    if (!platform || !formatId)
        return undefined;
    return platform.formats.find((f) => f.id === formatId);
}
/** Every format id any platform supports, for the schema's options list. */
export const ALL_FORMATS = [
    { value: 'feed_image', title: 'Feed image' },
    { value: 'carousel', title: 'Carousel / multi-image' },
    { value: 'reel', title: 'Reel' },
    { value: 'story', title: 'Story' },
    { value: 'video', title: 'Video' },
    { value: 'text', title: 'Text only' },
    { value: 'link', title: 'Link share' },
];
/** Hashtags written anywhere in the caption body. */
export function extractHashtags(caption) {
    return caption.match(/(^|\s)(#[\p{L}\p{N}_]+)/gu)?.map((t) => t.trim()) ?? [];
}
export function extractUrls(caption) {
    return caption.match(/https?:\/\/[^\s]+/g) ?? [];
}
/** How close a ratio has to be to count as that ratio. */
const RATIO_TOLERANCE = 0.02;
export function ratioMatches(actual, target) {
    return Math.abs(actual - target.value) / target.value <= RATIO_TOLERANCE;
}
