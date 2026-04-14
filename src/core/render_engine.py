"""
render_engine.py — 防伪矩阵深度渲染内核

负责最纯粹的底层光学级图片计算：包含正片叠底混色，干枯斑驳印泥生成，以及骑缝分层扰动切片。
彻底打破传统电子文印僵硬感，模拟印泥深沁与装订受阻带来的像素级损耗物理瑕疵特征。
"""

import math
import random
import numpy as np
from PIL import Image, ImageEnhance

class RenderEngine:
    
    @staticmethod
    def multiply_blend(bg_image: Image.Image, fg_image: Image.Image, position: tuple[int, int]) -> Image.Image:
        """
        正片叠底叠加算法。
        使得红色印章压黑字时产生纸张沁人渗透感而使得原黑字不透掩，不反光。
        严格防御 Alpha 预乘漏洞引发的变黑。
        
        Args:
            bg_image (PIL.Image): 纸张文档的底图 (RGBA / RGB)
            fg_image (PIL.Image): 待压印章带有透明度的图片 (RGBA)
            position (tuple): (x, y) 压图锚点坐标

        Returns:
            合成叠加后的底层图表 Image.Image
        """
        bg = bg_image.convert("RGBA")
        fg = fg_image.convert("RGBA")
        
        # 将像素流向 numpy 高维矩阵进行转化
        # 因为正片叠底仅在 FG（印章）的非透明范围才起效！
        fg_np = np.array(fg).astype(np.float32) / 255.0
        
        bg_width, bg_height = bg.size
        fg_width, fg_height = fg.size
        x, y = position
        
        # 边界矩阵裁切运算：如果印章印出纸外，需要剔除掉外面不加干涉的多出部位
        x_min = max(0, x)
        y_min = max(0, y)
        x_max = min(bg_width, x + fg_width)
        y_max = min(bg_height, y + fg_height)
        
        # 如果彻底在文档外边，直接放弃不印
        if x_min >= x_max or y_min >= y_max:
            return bg
            
        fg_x_min = x_min - x
        fg_y_min = y_min - y
        fg_x_max = fg_x_min + (x_max - x_min)
        fg_y_max = fg_y_min + (y_max - y_min)
        
        bg_np = np.array(bg).astype(np.float32) / 255.0
        
        # 裁剪出交集区
        bg_roi = bg_np[y_min:y_max, x_min:x_max]
        fg_roi = fg_np[fg_y_min:fg_y_max, fg_x_min:fg_x_max]
        
        # 提取前置图的 Alpha 层
        fg_alpha = fg_roi[:, :, 3:4]
        
        # 色彩叠加主方程：将色彩通道 [R, G, B] 进行正片重乘
        # Multiply: C_res = C_bg * C_fg
        color_multiply = bg_roi[:, :, :3] * fg_roi[:, :, :3]
        
        # Alpha 权重融合：有颜料的地方等于乘后结果，没颜料(背景是透明)的地方直接等于白底
        blended_roi_rgb = color_multiply * fg_alpha + bg_roi[:, :, :3] * (1.0 - fg_alpha)
        
        # 将新产出的矩阵缝合进原大图
        bg_np[y_min:y_max, x_min:x_max, :3] = blended_roi_rgb
        
        # 将其拉回自然数 RGB 光电阈值并锁止
        final_out = np.clip(bg_np * 255, 0, 255).astype(np.uint8)
        return Image.fromarray(final_out, "RGBA")

    @staticmethod
    def apply_stamp_dirt(stamp_image: Image.Image, intensity: float = 0.15) -> Image.Image:
        """
        干枯/脱色/斑驳随机断点遮罩腐烂术。
        让完美平滑数字色块呈现受纸张肌理干扰的脱墨态！
        
        Args:
            stamp_image (PIL.Image): 需要做旧的源印章
            intensity: 腐烂阈值系数，0 没有脱墨 -> 1 基本隐形
        """
        if intensity <= 0.0:
            return stamp_image
            
        stamp_np = np.array(stamp_image.convert("RGBA"))
        
        w, h = stamp_image.size
        # 生成高频底噪
        noise = np.random.uniform(0, 1, (h, w))
        
        # 只提取有红色/蓝色油墨区，如果本就透明不予攻击。过滤印泥区域。
        alpha_channel = stamp_np[:, :, 3]
        colored_mask = alpha_channel > 50
        
        # 强力剔除: 随机点内如果高于一定强度则将被打穿至死（Alpha设为 0）
        # 让脱色表现为油墨从纸中被抠掉
        erode_mask = (noise < (intensity * 0.5)) & colored_mask
        
        # 为了进一步写实感，削弱没被打穿的保留分部，使得印泥变暗变脏。
        stamp_np[erode_mask, 3] = 0        # 完全脱落
        
        # 紧急避险：由于 stamp_np 是 uint8，乘浮点数 0.9 后需要强转才能安全写回矩阵空间
        darkened = stamp_np[colored_mask & ~erode_mask, :3] * 0.9
        stamp_np[colored_mask & ~erode_mask, :3] = darkened.astype(np.uint8)
        
        return Image.fromarray(stamp_np, "RGBA")

    @staticmethod
    def split_binding_stamp(stamp_image: Image.Image, pages_count: int, 
                          edge_loss: int = 4, displacement: float = 2.0) -> list[Image.Image]:
        """
        骑缝章全能撕裂生成器。负责切分，丢边，位移，从而构成自然接缝瑕疵阵。
        
        Args:
            stamp_image (PIL): 印原身
            pages_count (int): 切为几折(页)
            edge_loss (int): 核心物理仿真参数：因为装订订书钉卷入夹缝而永不可见的像素量损毁。
            displacement (float): 模拟上下没有对齐时产生的微位移系数
            
        Returns:
            list[Image.Image]: 撕裂后的碎块，可以分发装载给每页。
        """
        w, h = stamp_image.size
        
        # 每折均宽（可能产生小数点误差抛弃，因为复印机光栅也不完美）
        part_width = w // pages_count
        
        slices = []
        for i in range(pages_count):
            # 切片坐标计算
            x1 = i * part_width
            # 最后一页把所有尾巴残余吃掉
            x2 = w if i == pages_count - 1 else x1 + part_width
            
            # 由于书籍夹扁的压痕遮挡，每一截靠近脊背的连接地带都会损毁一溜
            # （第0页无左脊缝损毁，最后极也没右脊缝损毁，只切里面互挨的刀口处）
            if i > 0:
                x1 += edge_loss
            if i < pages_count - 1:
                x2 -= edge_loss
                
            y1 = 0
            y2 = h
            
            # 使用 PIL crop() 切下这块图
            cropped = stamp_image.crop((x1, y1, x2, y2))
            
            # 给分块附加纵向滑移抖动，代表人工印书时不可能 100% 水平。
            # 这里在 np 进行，或者直接使用 PIL 画去新的带抖动的透明画布。
            cw, ch = cropped.size
            if displacement > 0.0:
                y_shift = random.uniform(-displacement, displacement)
                shifted_image = Image.new("RGBA", (cw, ch + int(math.ceil(2 * displacement))), (0, 0, 0, 0))
                # 贴上去加偏移
                shifted_image.paste(cropped, (0, int(math.ceil(displacement + y_shift))))
                cropped = shifted_image
                
            slices.append(cropped)
            
        return slices

    @staticmethod
    def synthesize_export(doc_model, stamps_dict: dict, binding_params: dict, assets_manager, decolor_params: dict = None, progress_callback=None) -> list[Image.Image]:
        """
        深度合成全导管：
        1. 获取每一页的已去色基底。
        2. 给每一页叠加所有 StampItem。应用比例缩放、旋转(expand)及印泥斑驳。
        3. 挂载指定页面的右侧切缝碎片。
        返回经过物理模拟合并（正片叠底汇合）的最终矩阵序列图。
        """
        out_images = []
        total_pages = doc_model.page_count
        
        # 预先生成所有的防伪缝切片以便对号入座
        binding_slices = []
        if binding_params.get("preview") and binding_params.get("asset_id"):
            asset_info = assets_manager.get_assets("stamps")
            target = next((a for a in asset_info if a["id"] == binding_params["asset_id"]), None)
            if target:
                b_path = assets_manager.get_absolute_path(target["path"])
                b_img = Image.open(b_path).convert("RGBA")
                
                # 支持从画布交互传入的精确参数，或退回自动推断
                interact = binding_params.get("interactive", {})
                
                scale_val = interact.get("scale")
                if scale_val is not None:
                    new_w = int(b_img.width * scale_val)
                    new_h = int(b_img.height * scale_val)
                    b_img = b_img.resize((max(1, new_w), max(1, new_h)), Image.Resampling.BICUBIC)
                else:             
                    first_page = doc_model.get_page(0)
                    if first_page:
                        target_w = first_page.width * 0.15
                        scale_ratio = target_w / b_img.width
                        scale_ratio = max(0.05, min(scale_ratio, 5.0))
                        if scale_ratio != 1.0:
                            new_w = int(b_img.width * scale_ratio)
                            new_h = int(b_img.height * scale_ratio)
                            b_img = b_img.resize((new_w, new_h), Image.Resampling.BICUBIC)
                            
                rotation = interact.get("rotation", 0.0)
                if rotation != 0.0:
                    b_img = b_img.rotate(-rotation, resample=Image.Resampling.BICUBIC, expand=True)
                
                start_p = binding_params["start_page"]
                end_p = binding_params["end_page"]
                pc = (end_p - start_p) + 1
                if pc >= 2:
                    slices = RenderEngine.split_binding_stamp(
                        b_img, pc, binding_params.get("loss", 4), binding_params.get("displacement", 2.0)
                    )
                    binding_slices = [None] * max(end_p + 1, total_pages)
                    for i, slc in enumerate(slices):
                        idx = start_p + i
                        if idx < len(binding_slices):
                            binding_slices[idx] = slc

        from src.core.cv_processor import CVProcessor
        from src.utils.image_utils import pil_to_numpy, numpy_to_pil

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
                    mode=decolor_params.get("mode", "otsu")
                )
                cv_img = CVProcessor.add_paper_noise(
                    cv_img,
                    intensity=decolor_params.get("noise_intensity", 0.03)
                )
                base_bg = numpy_to_pil(cv_img).convert("RGBA")
            else:
                base_bg = orig_pil.copy().convert("RGBA")
                
            bg_w, bg_h = base_bg.size
            
            # 合成页面内单独盖印的所有印章
            # stamps_dict structure: { page_index (int): [ {"asset_id": "...", "x": float, "y": float, "scale": float, "rotation": float}, ... ] }
            page_stamps = stamps_dict.get(p_idx, [])
            for st in page_stamps:
                # 遍历 stamps 和 signatures 查库
                all_assets = assets_manager.get_assets("stamps") + assets_manager.get_assets("signatures")
                target = next((a for a in all_assets if a["id"] == st["asset_id"]), None)
                if not target:
                    continue
                s_path = assets_manager.get_absolute_path(target["path"])
                fg_img = Image.open(s_path).convert("RGBA")
                
                # 1. 缩放
                if st["scale"] != 1.0:
                    nw = int(fg_img.width * st["scale"])
                    nh = int(fg_img.height * st["scale"])
                    if nw > 0 and nh > 0:
                        fg_img = fg_img.resize((nw, nh), Image.Resampling.BICUBIC)
                
                # 2. 腐烂破损印泥模拟
                fg_img = RenderEngine.apply_stamp_dirt(fg_img, intensity=0.15)
                
                # 3. 旋转 (扩充画布防止被裁切)
                if st["rotation"] != 0.0:
                    # Qt图元正向是顺时针，PIL .rotate 正向是逆时针，需加负号
                    fg_img = fg_img.rotate(-st["rotation"], resample=Image.Resampling.BICUBIC, expand=True)
                
                # 4. 计算左上角锚点。给定的是中央物理坐标 x/y。
                cx = st["x"]  
                cy = st["y"]
                top_left_x = int(cx - (fg_img.width / 2.0))
                top_left_y = int(cy - (fg_img.height / 2.0))
                
                base_bg = RenderEngine.multiply_blend(base_bg, fg_img, (top_left_x, top_left_y))
            
            # 合成侧边缝章切片
            if binding_slices and p_idx < len(binding_slices) and binding_slices[p_idx]:
                bslc = binding_slices[p_idx]
                bslc = RenderEngine.apply_stamp_dirt(bslc, intensity=0.15)
                
                slc_w, slc_h = bslc.size
                margin = binding_params.get("margin", 0)
                bx = bg_w - slc_w - margin
                interact = binding_params.get("interactive", {})
                if interact.get("y") is not None:
                    cy = interact.get("y")
                    by = int(cy - (slc_h / 2.0))
                else:
                    by = int((bg_h - slc_h) / 2.0)
                base_bg = RenderEngine.multiply_blend(base_bg, bslc, (bx, by))
            
            # 将合并了多层的图像封层为标准 RGB 并保存
            out_images.append(base_bg.convert("RGB"))
            
        return out_images
