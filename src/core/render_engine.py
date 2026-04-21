"""
Core rendering utilities for export compositing.
"""

import math
import random

import numpy as np
from PIL import Image


class RenderEngine:
    A4_WIDTH_PX = 2480
    A4_HEIGHT_PX = 3508
    BINDING_TARGET_WIDTH_RATIO = 0.15

    @staticmethod
    def get_page_to_a4_scale(page_width: float, page_height: float) -> float:
        """Scale factor when fitting a page into an A4 canvas."""
        if page_width <= 0 or page_height <= 0:
            return 0.0
        return min(RenderEngine.A4_WIDTH_PX / float(page_width), RenderEngine.A4_HEIGHT_PX / float(page_height))

    @staticmethod
    def binding_target_width_on_a4(user_scale: float = 1.0) -> int:
        """Target binding stamp width in A4-space pixels."""
        safe_user_scale = max(0.01, float(user_scale))
        return max(1, int(round(RenderEngine.A4_WIDTH_PX * RenderEngine.BINDING_TARGET_WIDTH_RATIO * safe_user_scale)))

    @staticmethod
    def binding_units_on_page(page_width: float, page_height: float, a4_units: float) -> float:
        """Convert A4-space pixels into current page-space pixels."""
        scale = RenderEngine.get_page_to_a4_scale(page_width, page_height)
        if scale <= 0:
            return 0.0
        return float(a4_units) / scale

    @staticmethod
    def multiply_blend(bg_image: Image.Image, fg_image: Image.Image, position: tuple[int, int]) -> Image.Image:
        """Multiply blend fg onto bg at top-left position."""
        bg = bg_image.convert("RGBA")
        fg = fg_image.convert("RGBA")

        fg_np = np.array(fg).astype(np.float32) / 255.0
        bg_np = np.array(bg).astype(np.float32) / 255.0

        bg_width, bg_height = bg.size
        fg_width, fg_height = fg.size
        x, y = position

        x_min = max(0, x)
        y_min = max(0, y)
        x_max = min(bg_width, x + fg_width)
        y_max = min(bg_height, y + fg_height)
        if x_min >= x_max or y_min >= y_max:
            return bg

        fg_x_min = x_min - x
        fg_y_min = y_min - y
        fg_x_max = fg_x_min + (x_max - x_min)
        fg_y_max = fg_y_min + (y_max - y_min)

        bg_roi = bg_np[y_min:y_max, x_min:x_max]
        fg_roi = fg_np[fg_y_min:fg_y_max, fg_x_min:fg_x_max]

        fg_alpha = fg_roi[:, :, 3:4]
        color_multiply = bg_roi[:, :, :3] * fg_roi[:, :, :3]
        blended_roi_rgb = color_multiply * fg_alpha + bg_roi[:, :, :3] * (1.0 - fg_alpha)
        bg_np[y_min:y_max, x_min:x_max, :3] = blended_roi_rgb

        final_out = np.clip(bg_np * 255, 0, 255).astype(np.uint8)
        return Image.fromarray(final_out, "RGBA")

    @staticmethod
    def apply_stamp_dirt(stamp_image: Image.Image, intensity: float = 0.15) -> Image.Image:
        """Add subtle random erosion to mimic real seal ink."""
        if intensity <= 0.0:
            return stamp_image

        stamp_np = np.array(stamp_image.convert("RGBA"))
        h, w = stamp_np.shape[:2]
        noise = np.random.uniform(0, 1, (h, w))

        alpha_channel = stamp_np[:, :, 3]
        colored_mask = alpha_channel > 50
        erode_mask = (noise < (intensity * 0.5)) & colored_mask
        stamp_np[erode_mask, 3] = 0

        darkened = stamp_np[colored_mask & ~erode_mask, :3] * 0.9
        stamp_np[colored_mask & ~erode_mask, :3] = darkened.astype(np.uint8)
        return Image.fromarray(stamp_np, "RGBA")

    @staticmethod
    def split_binding_stamp(
        stamp_image: Image.Image,
        pages_count: int,
        edge_loss: int = 4,
        displacement: float = 2.0,
    ) -> list[Image.Image]:
        """Split binding stamp into page slices with seam loss and vertical drift."""
        w, h = stamp_image.size
        if pages_count <= 0:
            return []

        edge_loss = max(0, int(edge_loss))
        slices = []
        for i in range(pages_count):
            seg_x1 = int(round((i * w) / float(pages_count)))
            seg_x2 = int(round(((i + 1) * w) / float(pages_count)))
            if i == pages_count - 1:
                seg_x2 = w
            seg_w = max(1, seg_x2 - seg_x1)

            x1 = seg_x1
            x2 = seg_x2
            if i > 0:
                x1 += edge_loss
            if i < pages_count - 1:
                x2 -= edge_loss

            if x2 <= x1:
                x1 = seg_x1
                x2 = min(w, seg_x1 + 1)

            ink = stamp_image.crop((x1, 0, x2, h))
            slice_canvas = Image.new("RGBA", (seg_w, h), (0, 0, 0, 0))
            paste_x = max(0, x1 - seg_x1)
            slice_canvas.paste(ink, (min(paste_x, max(0, seg_w - ink.width)), 0))

            cw, ch = slice_canvas.size
            if displacement > 0.0:
                y_shift = random.uniform(-displacement, displacement)
                shifted = Image.new("RGBA", (cw, ch + int(math.ceil(2 * displacement))), (0, 0, 0, 0))
                shifted.paste(slice_canvas, (0, int(math.ceil(displacement + y_shift))))
                slice_canvas = shifted
            slices.append(slice_canvas)
        return slices

    @staticmethod
    def _find_binding_reference_width_a4(
        doc_model,
        stamps_dict: dict,
        binding_params: dict,
        asset_width_px: int,
    ) -> float | None:
        if asset_width_px <= 0:
            return None

        asset_id = binding_params.get("asset_id")
        if not asset_id:
            return None

        total_pages = max(0, int(getattr(doc_model, "page_count", 0)))
        if total_pages <= 0:
            return None

        start_p = max(0, min(int(binding_params.get("start_page", 0)), total_pages - 1))
        end_p = max(0, min(int(binding_params.get("end_page", total_pages - 1)), total_pages - 1))
        if end_p < start_p:
            start_p, end_p = end_p, start_p

        search_pages = list(range(start_p, end_p + 1)) + [i for i in range(total_pages) if i < start_p or i > end_p]

        for page_idx in search_pages:
            for st in stamps_dict.get(page_idx, []):
                if st.get("asset_id") != asset_id:
                    continue

                stamp_scale = float(st.get("scale", 1.0))
                if stamp_scale <= 0:
                    continue

                page_img = doc_model.get_original_page(page_idx)
                if not page_img:
                    continue

                page_to_a4 = RenderEngine.get_page_to_a4_scale(page_img.width, page_img.height)
                if page_to_a4 <= 0:
                    continue

                width_page = float(asset_width_px) * stamp_scale
                width_a4 = width_page * page_to_a4
                if width_a4 > 1.0:
                    return width_a4

        return None

    @staticmethod
    def _build_binding_slices_a4(doc_model, stamps_dict: dict, binding_params: dict, assets_manager):
        slices_by_page = []
        if not binding_params.get("preview") or not binding_params.get("asset_id"):
            return slices_by_page

        asset_info = assets_manager.get_assets("stamps")
        target = next((a for a in asset_info if a["id"] == binding_params["asset_id"]), None)
        if not target:
            return slices_by_page

        b_path = assets_manager.get_absolute_path(target["path"])
        b_img = Image.open(b_path).convert("RGBA")

        forced_target_width_a4 = float(binding_params.get("target_width_a4", 0.0) or 0.0)
        if forced_target_width_a4 > 1.0:
            target_w_a4 = max(1, int(round(forced_target_width_a4)))
        else:
            user_scale = max(0.01, float(binding_params.get("scale", 1.0)))
            ref_width_a4 = RenderEngine._find_binding_reference_width_a4(
                doc_model,
                stamps_dict,
                binding_params,
                b_img.width,
            )
            if ref_width_a4 is None:
                base_width_a4 = RenderEngine.binding_target_width_on_a4(1.0)
            else:
                base_width_a4 = ref_width_a4
            target_w_a4 = max(1, int(round(base_width_a4 * user_scale)))
        if b_img.width > 0:
            target_h_a4 = max(1, int(round(b_img.height * (target_w_a4 / float(b_img.width)))))
            b_img = b_img.resize((target_w_a4, target_h_a4), Image.Resampling.BICUBIC)

        rotation = float(binding_params.get("rotation", 0.0))
        if rotation != 0.0:
            b_img = b_img.rotate(-rotation, resample=Image.Resampling.BICUBIC, expand=True)

        start_p = int(binding_params.get("start_page", 0))
        end_p = int(binding_params.get("end_page", 0))
        page_count = (end_p - start_p) + 1
        if page_count < 2:
            return slices_by_page

        slices = RenderEngine.split_binding_stamp(
            b_img,
            page_count,
            int(binding_params.get("loss", 4)),
            float(binding_params.get("displacement", 2.0)),
        )

        total_pages = doc_model.page_count
        slices_by_page = [None] * max(total_pages, end_p + 1)
        for i, slc in enumerate(slices):
            idx = start_p + i
            if 0 <= idx < len(slices_by_page):
                slices_by_page[idx] = slc
        return slices_by_page

    @staticmethod
    def synthesize_export(
        doc_model,
        stamps_dict: dict,
        binding_params: dict,
        assets_manager,
        decolor_params: dict = None,
        progress_callback=None,
    ) -> list[Image.Image]:
        """Compose per-page output images for export."""
        from src.core.cv_processor import CVProcessor
        from src.utils.image_utils import pil_to_numpy, numpy_to_pil

        out_images = []
        total_pages = doc_model.page_count
        binding_slices_a4 = RenderEngine._build_binding_slices_a4(doc_model, stamps_dict, binding_params, assets_manager)

        for p_idx in range(total_pages):
            if progress_callback:
                progress_callback(p_idx, total_pages)

            orig_pil = doc_model.get_original_page(p_idx)
            if not orig_pil:
                continue

            if decolor_params and decolor_params.get("enabled"):
                cv_img = pil_to_numpy(orig_pil)
                cv_img = CVProcessor.decolorize(
                    cv_img,
                    threshold=decolor_params.get("threshold", 120),
                    mode=decolor_params.get("mode", "otsu"),
                )
                cv_img = CVProcessor.add_paper_noise(
                    cv_img,
                    intensity=decolor_params.get("noise_intensity", 0.03),
                )
                base_bg = numpy_to_pil(cv_img).convert("RGBA")
            else:
                base_bg = orig_pil.copy().convert("RGBA")

            bg_w, bg_h = base_bg.size

            page_stamps = stamps_dict.get(p_idx, [])
            for st in page_stamps:
                all_assets = assets_manager.get_assets("stamps") + assets_manager.get_assets("signatures")
                target = next((a for a in all_assets if a["id"] == st["asset_id"]), None)
                if not target:
                    continue

                s_path = assets_manager.get_absolute_path(target["path"])
                fg_img = Image.open(s_path).convert("RGBA")

                if st["scale"] != 1.0:
                    nw = int(fg_img.width * st["scale"])
                    nh = int(fg_img.height * st["scale"])
                    if nw > 0 and nh > 0:
                        fg_img = fg_img.resize((nw, nh), Image.Resampling.BICUBIC)

                fg_img = RenderEngine.apply_stamp_dirt(fg_img, intensity=0.15)

                if st["rotation"] != 0.0:
                    fg_img = fg_img.rotate(-st["rotation"], resample=Image.Resampling.BICUBIC, expand=True)

                cx = st["x"]
                cy = st["y"]
                top_left_x = int(cx - (fg_img.width / 2.0))
                top_left_y = int(cy - (fg_img.height / 2.0))
                base_bg = RenderEngine.multiply_blend(base_bg, fg_img, (top_left_x, top_left_y))

            if binding_slices_a4 and p_idx < len(binding_slices_a4) and binding_slices_a4[p_idx] is not None:
                slice_a4 = binding_slices_a4[p_idx]
                page_to_a4 = RenderEngine.get_page_to_a4_scale(bg_w, bg_h)
                if page_to_a4 > 0:
                    slc_w = max(1, int(round(slice_a4.width / page_to_a4)))
                    slc_h = max(1, int(round(slice_a4.height / page_to_a4)))
                    bslc = slice_a4.resize((slc_w, slc_h), Image.Resampling.BICUBIC)
                    bslc = RenderEngine.apply_stamp_dirt(bslc, intensity=0.15)

                    margin_a4 = max(0, abs(int(binding_params.get("margin", 15))))
                    margin = int(round(RenderEngine.binding_units_on_page(bg_w, bg_h, margin_a4)))
                    bx = max(0, min(bg_w - slc_w - margin, bg_w - slc_w))

                    interact = binding_params.get("interactive", {})
                    if interact.get("y") is not None:
                        cy = interact.get("y")
                        by = int(cy - (slc_h / 2.0))
                    else:
                        by = int((bg_h - slc_h) / 2.0)

                    base_bg = RenderEngine.multiply_blend(base_bg, bslc, (bx, by))

            out_images.append(base_bg.convert("RGB"))

        return out_images
