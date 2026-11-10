package com.nodecockpit.customization;

import android.content.Context;
import android.net.Uri;
import android.os.CancellationSignal;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/** Photos' own content-URI lookup and one-up viewer for a dedup-key collection. */
final class CloudCameraMedia {
    record Photo(Object nativeMedia, Uri thumbnail) {}
    record Collection(Object nativeCollection, List<Photo> photos) {}

    private final Method dedupKey;
    private final Constructor<?> collection;
    private final Method wrapCollection;
    private final Method loadMedia;
    private final Object uriQuery;
    private final Constructor<?> uriLookup;
    private final Method uriProvider;
    private final Method uriForPhoto;
    private final Method originalUriForPhoto;
    private final Object originalBytes;
    private final Constructor<?> pager;
    private final Method pagerCollection;
    private final Method pagerQuery;
    private final Object pagerOptions;
    private final Method resolveService;
    private final Class<?> viewerService;
    private final Method showPhoto;

    CloudCameraMedia(ClassLoader loader) throws ReflectiveOperationException {
        Class<?> media = loader.loadClass("calt");
        Class<?> mediaCollection = loader.loadClass("calu");
        Class<?> provider = loader.loadClass("zvh");
        Class<?> options = loader.loadClass("yvg");
        Class<?> pagerType = loader.loadClass("ascp");
        viewerService = loader.loadClass("asdu");
        dedupKey = loader.loadClass("akff").getMethod("a", String.class);
        collection = loader.loadClass("ptp").getConstructor(int.class, List.class, boolean.class);
        wrapCollection = loader.loadClass("ywt").getMethod("a", mediaCollection);
        loadMedia = loader.loadClass("yvx").getMethod(
                "E", Context.class, loader.loadClass("ywl"), loader.loadClass("yuq"));
        var query = provider.getDeclaredField("b");
        query.setAccessible(true);
        uriQuery = query.get(null);
        uriLookup = provider.getConstructor(Context.class);
        uriProvider = provider.getDeclaredMethod("c");
        uriProvider.setAccessible(true);
        uriForPhoto = loader.loadClass("yqj").getMethod("a", media);
        Class<?> rendition = loader.loadClass("yqi");
        originalUriForPhoto = loader.loadClass("yqk").getMethod("f", media, rendition, int.class);
        originalBytes = rendition.getField("f").get(null);
        pager = pagerType.getConstructor(Context.class);
        pagerCollection = pagerType.getMethod("am", mediaCollection);
        pagerQuery = pagerType.getMethod("ai", options);
        pagerOptions = options.getField("a").get(null);
        resolveService = loader.loadClass("cdht").getMethod("e", Context.class, Class.class);
        showPhoto = viewerService.getMethod("h", media, loader.loadClass("asdy"), pagerType);
    }

    Collection load(Context context, int account, List<String> keys, CancellationSignal request)
            throws ReflectiveOperationException {
        List<Object> nativeKeys = new ArrayList<>(keys.size());
        for (String key : keys) nativeKeys.add(dedupKey.invoke(null, key));
        Object nativeCollection = collection.newInstance(account, nativeKeys, true);
        List<?> matches = (List<?>) loadMedia.invoke(
                null, context, wrapCollection.invoke(null, nativeCollection), uriQuery);
        Object provider = uriProvider.invoke(uriLookup.newInstance(context));
        List<Photo> photos = new ArrayList<>(matches.size());
        for (Object match : matches) {
            request.throwIfCanceled();
            photos.add(new Photo(match, (Uri) uriForPhoto.invoke(provider, match)));
        }
        return new Collection(nativeCollection, photos);
    }

    void open(Context context, Collection collection, Photo photo) throws ReflectiveOperationException {
        Object builder = pager.newInstance(context);
        pagerCollection.invoke(builder, collection.nativeCollection());
        pagerQuery.invoke(builder, pagerOptions);
        Object service = resolveService.invoke(null, context, viewerService);
        showPhoto.invoke(service, photo.nativeMedia(), null, builder);
    }

    Uri originalUri(Context context, int account, String key, CancellationSignal request)
            throws ReflectiveOperationException {
        Collection match = load(context, account, List.of(key), request);
        if (match.photos().size() != 1) return null;
        Object provider = uriProvider.invoke(uriLookup.newInstance(context));
        return (Uri) originalUriForPhoto.invoke(provider, match.photos().get(0).nativeMedia(), originalBytes, 1);
    }
}
