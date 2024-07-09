Mix.install(
  [
    :ex_vision,
    :kino,
    :kino_bumblebee,
    :stb_image,
    :exla,
    :image
  ],
  config: [
    nx: [default_backend: EXLA.Backend]
  ]
)

alias ExVision.Classification.MobileNetV3Small, as: Classifier
alias ExVision.ObjectDetection.FasterRCNN_ResNet50_FPN, as: ObjectDetector
alias ExVision.SemanticSegmentation.DeepLabV3_MobileNetV3, as: SemanticSegmentation
alias ExVision.InstanceSegmentation.MaskRCNN_ResNet50_FPN_V2, as: InstanceSegmentation
alias ExVision.KeypointDetection.KeypointRCNN_ResNet50_FPN, as: KeypointDetector

{:ok, classifier} = Classifier.load()
{:ok, object_detector} = ObjectDetector.load()
{:ok, semantic_segmentation} = SemanticSegmentation.load()
{:ok, instance_segmentation} = InstanceSegmentation.load()
{:ok, keypoint_detector} = KeypointDetector.load()

