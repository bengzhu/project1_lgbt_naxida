# Comic Text and Bubble Detector notice

AITRANS bundles a Core ML conversion of
[`ogkalu/comic-text-and-bubble-detector`](https://huggingface.co/ogkalu/comic-text-and-bubble-detector)
at revision `16e8a622f91fabc6b5b65c96d32d1183f8843546`.

- Upstream architecture: RT-DETR-v2 R50
- Upstream labels: `bubble`, `text_bubble`, `text_free`
- AITRANS input: RGB 640 x 640, scaled by 1/255
- AITRANS outputs: `logits [1,300,3]`, `pred_boxes [1,300,4]`
- Text labels: IDs 1 and 2 with sigmoid confidence at least 0.30
- Conversion: Core ML program, FP16 compute, linear-symmetric INT8 weights
- Minimum deployment target: iOS 17

The upstream model is distributed under Apache License 2.0. A copy is bundled
as `ComicTextDetector-LICENSE-APACHE`. The Core ML conversion does not change
the upstream license or imply ownership of the source model.
