import Foundation

struct BindingStampDrawPlan: Equatable {
    var pageOffset: Int
    var pageCount: Int
    var originXMM: Double
    var originYMM: Double
    var widthMM: Double
    var heightMM: Double
    var rotation: Double
}

struct BindingStampSliceCrop: Equatable {
    var x: Int
    var width: Int
    var height: Int
}

protocol BindingStampService {
    func makeDefaultPlacement(
        pageCount: Int,
        preferredAssetID: UUID?,
        fallbackAssetID: UUID?,
        suggestedWidthMM: Double?
    ) -> BindingStampPlacement

    func normalizePlacement(_ placement: BindingStampPlacement, pageCount: Int) -> BindingStampPlacement

    func drawPlan(
        for pageIndex: Int,
        documentPageCount: Int,
        pageSizeMM: MillimeterSize,
        placement: BindingStampPlacement,
        aspectRatio: Double?
    ) -> BindingStampDrawPlan?

    func sliceCrop(
        forImageWidth imageWidth: Int,
        imageHeight: Int,
        pageOffset: Int,
        pageCount: Int
    ) -> BindingStampSliceCrop?
}

struct DefaultBindingStampService: BindingStampService {
    func makeDefaultPlacement(
        pageCount: Int,
        preferredAssetID: UUID?,
        fallbackAssetID: UUID?,
        suggestedWidthMM: Double?
    ) -> BindingStampPlacement {
        let validPageCount = max(pageCount, 1)
        let widthMM = suggestedWidthMM ?? 40.0
        return BindingStampPlacement(
            assetID: preferredAssetID ?? fallbackAssetID ?? UUID(),
            startPage: 0,
            endPage: validPageCount - 1,
            targetWidthMM: min(max(widthMM, 10.0), 300.0),
            marginMM: 3.0,
            lossMM: 0.5,
            rotation: 0.0,
            yOffsetMM: 0.0,
            enabled: false
        )
    }

    func normalizePlacement(_ placement: BindingStampPlacement, pageCount: Int) -> BindingStampPlacement {
        var normalized = placement
        let validPageCount = max(pageCount, 1)
        let lastPage = validPageCount - 1

        normalized.startPage = min(max(normalized.startPage, 0), lastPage)
        normalized.endPage = min(max(normalized.endPage, normalized.startPage), lastPage)
        normalized.targetWidthMM = min(max(normalized.targetWidthMM, 10.0), 300.0)
        normalized.marginMM = min(max(normalized.marginMM, 0.0), 40.0)
        normalized.lossMM = min(max(normalized.lossMM, 0.0), 15.0)
        normalized.rotation = min(max(normalized.rotation, -45.0), 45.0)
        normalized.yOffsetMM = min(max(normalized.yOffsetMM, -120.0), 120.0)

        return normalized
    }

    func drawPlan(
        for pageIndex: Int,
        documentPageCount: Int,
        pageSizeMM: MillimeterSize,
        placement: BindingStampPlacement,
        aspectRatio: Double?
    ) -> BindingStampDrawPlan? {
        guard placement.enabled else {
            return nil
        }

        let normalized = normalizePlacement(placement, pageCount: documentPageCount)
        guard pageIndex >= normalized.startPage, pageIndex <= normalized.endPage else {
            return nil
        }

        let pageCount = normalized.endPage - normalized.startPage + 1
        guard pageCount > 0 else {
            return nil
        }

        let pageOffset = pageIndex - normalized.startPage
        let totalWidthMM = max(normalized.targetWidthMM, 10.0)
        let sliceWidthMMBase = totalWidthMM / Double(pageCount)
        let drawWidthMM = min(max(sliceWidthMMBase + normalized.lossMM, 1.0), pageSizeMM.width)
        let resolvedAspectRatio = max(aspectRatio ?? 1.0, 0.1)
        let drawHeightMM = min(max(totalWidthMM / resolvedAspectRatio, 8.0), pageSizeMM.height)

        let maxOriginX = max(pageSizeMM.width - drawWidthMM, 0.0)
        let originXMM = min(
            max(pageSizeMM.width - normalized.marginMM - drawWidthMM, 0.0),
            maxOriginX
        )

        let centeredYMM = (pageSizeMM.height - drawHeightMM) / 2.0
        let maxOriginY = max(pageSizeMM.height - drawHeightMM, 0.0)
        let originYMM = min(
            max(centeredYMM + normalized.yOffsetMM, 0.0),
            maxOriginY
        )

        return BindingStampDrawPlan(
            pageOffset: pageOffset,
            pageCount: pageCount,
            originXMM: originXMM,
            originYMM: originYMM,
            widthMM: drawWidthMM,
            heightMM: drawHeightMM,
            rotation: normalized.rotation
        )
    }

    func sliceCrop(
        forImageWidth imageWidth: Int,
        imageHeight: Int,
        pageOffset: Int,
        pageCount: Int
    ) -> BindingStampSliceCrop? {
        guard imageWidth > 0, imageHeight > 0 else {
            return nil
        }

        guard pageCount > 0, pageOffset >= 0, pageOffset < pageCount else {
            return nil
        }

        let rawSliceWidth = max(imageWidth / pageCount, 1)
        let sliceX = min(pageOffset * rawSliceWidth, imageWidth - 1)

        let sliceWidth: Int
        if pageOffset == pageCount - 1 {
            sliceWidth = max(imageWidth - sliceX, 1)
        } else {
            sliceWidth = max(min(rawSliceWidth, imageWidth - sliceX), 1)
        }

        return BindingStampSliceCrop(
            x: sliceX,
            width: sliceWidth,
            height: imageHeight
        )
    }
}
