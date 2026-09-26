// GENERATED FILE — do not edit.
//
// Compiled from lib/preflight.ts in the everfluorescent-cms repository, which is the
// single source of truth for every platform limit in both halves of the post
// queue. Change it THERE and run `npm run vendor` in publisher/.
//
// Source set hash: 79d156150fd1bc92

/**
 * preflight — the checks that stand between a variant and the publish queue.
 *
 * Every rule here reads its numbers from lib/platformSpec.ts, which is the same
 * file the preview components render from. If the preview says a caption fits,
 * this agrees; if this blocks, the preview is showing you why.
 *
 * Errors block approval. Warnings are shown and ignored — they are judgement
 * calls (a caption longer than what performs well) rather than things the API
 * will reject.
 */
import { extractHashtags, extractUrls, getFormat, getPlatform, ratioMatches, } from "./platformSpec.js";
function ratioLabel(a) {
    if (!a.width || !a.height)
        return 'unknown';
    const r = a.width / a.height;
    return `${a.width}×${a.height} (${r.toFixed(2)}:1)`;
}
export function preflight(variant) {
    const issues = [];
    const platform = getPlatform(variant.platform);
    const format = getFormat(variant.platform, variant.format);
    const caption = variant.caption ?? '';
    const hashtags = extractHashtags(caption);
    const assets = variant.assets ?? [];
    if (!platform) {
        issues.push({ level: 'error', field: 'platform', message: 'No platform chosen.' });
        return finish(issues, undefined, undefined, caption.length, hashtags.length);
    }
    if (!format) {
        issues.push({
            level: 'error',
            field: 'format',
            message: `Choose a format. ${platform.label} supports ${platform.formats
                .map((f) => f.label)
                .join(', ')}.`,
        });
    }
    // --- caption -------------------------------------------------------------
    if (!caption.trim()) {
        issues.push({ level: 'error', field: 'caption', message: 'Caption is empty.' });
    }
    if (caption.length > platform.caption.max) {
        issues.push({
            level: 'error',
            field: 'caption',
            message: `Caption is ${caption.length} characters; ${platform.label} allows ${platform.caption.max}.`,
        });
    }
    else if (caption.length > platform.caption.recommended) {
        issues.push({
            level: 'warning',
            field: 'caption',
            message: `Caption is ${caption.length} characters. Over about ${platform.caption.recommended}, ${platform.label} truncates it behind a "more" link in the feed.`,
        });
    }
    // --- hashtags ------------------------------------------------------------
    if (hashtags.length > platform.hashtags.max) {
        issues.push({
            level: 'error',
            field: 'caption',
            message: `${hashtags.length} hashtags; ${platform.label} allows ${platform.hashtags.max}.`,
        });
    }
    else if (hashtags.length > platform.hashtags.recommended) {
        issues.push({
            level: 'warning',
            field: 'caption',
            message: `${hashtags.length} hashtags is more than the ${platform.hashtags.recommended} that usually reads well on ${platform.label}.`,
        });
    }
    // --- links ---------------------------------------------------------------
    const urls = extractUrls(caption);
    if (urls.length && !platform.linksClickable) {
        issues.push({
            level: 'warning',
            field: 'caption',
            message: `Links are not tappable in the ${platform.label} caption. Point people at the profile link instead of pasting ${urls[0]}.`,
        });
    }
    // --- assets --------------------------------------------------------------
    if (format) {
        if (assets.length < format.minAssets) {
            issues.push({
                level: 'error',
                field: 'assets',
                message: `${format.label} needs at least ${format.minAssets} asset${format.minAssets === 1 ? '' : 's'}; ${assets.length} attached.`,
            });
        }
        if (assets.length > format.maxAssets) {
            issues.push({
                level: 'error',
                field: 'assets',
                message: `${format.label} takes at most ${format.maxAssets}; ${assets.length} attached.`,
            });
        }
        assets.forEach((asset, i) => {
            const where = asset.filename ? `"${asset.filename}"` : `asset ${i + 1}`;
            if (format.imageMimeTypes && !asset.isVideo && asset.mimeType) {
                if (!format.imageMimeTypes.includes(asset.mimeType)) {
                    // Not an error: the asset CDN transcodes on request, so this is a
                    // note about how the worker must ask for the file, not a reason to
                    // stop Anna queueing a post that will publish perfectly well.
                    issues.push({
                        level: 'warning',
                        field: 'assets',
                        message: `${where} is ${asset.mimeType}, and the ${platform.label} publishing API only accepts ${format.imageMimeTypes.join(', ')}. It will be converted on delivery rather than published as stored.`,
                    });
                }
            }
            if (format.ratios.length && asset.width && asset.height) {
                const actual = asset.width / asset.height;
                const fits = format.ratios.some((r) => ratioMatches(actual, r));
                if (!fits) {
                    issues.push({
                        level: 'warning',
                        field: 'assets',
                        message: `${where} is ${ratioLabel(asset)}. ${platform.label} ${format.label} expects ${format.ratios.map((r) => r.label).join(' or ')} — it will be cropped.`,
                    });
                }
            }
            if (format.duration && asset.isVideo) {
                const { minSeconds, maxSeconds } = format.duration;
                if (asset.durationSeconds == null) {
                    // Saying nothing here would let the limit look enforced when it is not.
                    issues.push({
                        level: 'warning',
                        field: 'assets',
                        message: `Could not read how long ${where} runs, so the ${minSeconds}–${maxSeconds}s ${platform.label} limit has not been checked.`,
                    });
                }
                else if (asset.durationSeconds < minSeconds || asset.durationSeconds > maxSeconds) {
                    issues.push({
                        level: 'error',
                        field: 'assets',
                        message: `${where} runs ${Math.round(asset.durationSeconds)}s. ${platform.label} ${format.label} accepts ${minSeconds}–${maxSeconds}s.`,
                    });
                }
            }
        });
    }
    // --- account -------------------------------------------------------------
    if (variant.accountConfigured === false) {
        issues.push({
            level: 'error',
            field: 'account',
            message: `No ${platform.label} account is configured yet, so the worker has nowhere to post.`,
        });
    }
    if (platform.id === 'tiktok' && variant.accountAudited === false) {
        issues.push({
            level: 'info',
            field: 'account',
            message: 'TikTok has not audited the app yet, so this will land as a draft in your TikTok inbox rather than posting publicly.',
        });
    }
    if (platform.id === 'instagram') {
        issues.push({
            level: 'info',
            field: 'assets',
            message: 'Instagram fetches media from a public URL at publish time — the worker uploads to a public bucket first.',
        });
    }
    for (const product of variant.products ?? []) {
        const missing = product.incomplete ?? [];
        if (missing.length) {
            issues.push({
                level: 'error',
                field: 'products',
                message: `${product.title || 'A product'} is missing ${missing.join(', ')}. ` +
                    `Fix it in the store; the next catalog sync clears this.`,
            });
        }
        if (product.storeStatus === 'unlisted') {
            issues.push({
                level: 'warning',
                field: 'products',
                message: `${product.title || 'A product'} is no longer in the storefront, so this post would send people to a dead page.`,
            });
        }
    }
    return finish(issues, platform, format, caption.length, hashtags.length);
}
function finish(issues, platform, format, captionLength, hashtagCount) {
    const errors = issues.filter((i) => i.level === 'error');
    const warnings = issues.filter((i) => i.level === 'warning');
    return {
        platform,
        format,
        issues,
        errors,
        warnings,
        ok: errors.length === 0,
        captionLength,
        hashtagCount,
    };
}
