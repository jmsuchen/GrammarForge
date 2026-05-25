import Foundation

protocol AIGradingService {
    func grade(answer: String, exercise: Exercise, skill: GrammarSkill) async -> GradingResult
}

struct MockAIGradingService: AIGradingService {
    func grade(answer: String, exercise: Exercise, skill: GrammarSkill) async -> GradingResult {
        let normalizedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedReference = exercise.referenceAnswer.lowercased()
        let isCorrect = normalizedAnswer == normalizedReference
            || normalizedAnswer.contains(corePhrase(for: skill))

        if isCorrect {
            return GradingResult(
                isCorrect: true,
                score: 92,
                correctedSentence: exercise.referenceAnswer,
                errorTypes: [],
                explanationCN: "句子结构和目标语法点使用稳定，可以继续提高表达自然度。",
                betterVersion: exercise.referenceAnswer,
                similarQuestionCN: nextSimilarQuestion(for: skill)
            )
        }

        return GradingResult(
            isCorrect: false,
            score: 68,
            correctedSentence: exercise.referenceAnswer,
            errorTypes: errorTypes(for: skill),
            explanationCN: explanation(for: skill),
            betterVersion: exercise.referenceAnswer,
            similarQuestionCN: nextSimilarQuestion(for: skill)
        )
    }

    private func corePhrase(for skill: GrammarSkill) -> String {
        switch skill.name {
        case "现在完成时":
            return "have"
        case "定语从句":
            return "that"
        case "时间介词":
            return "since"
        default:
            return ""
        }
    }

    private func errorTypes(for skill: GrammarSkill) -> [String] {
        switch skill.module {
        case "时态系统":
            return ["时态错误"]
        case "从句系统":
            return ["从句错误"]
        case "介词搭配":
            return ["介词错误"]
        default:
            return ["句子结构错误"]
        }
    }

    private func explanation(for skill: GrammarSkill) -> String {
        switch skill.name {
        case "现在完成时":
            return "这里强调动作从过去持续到现在，通常需要使用 have/has done 或 have/has been doing。"
        case "定语从句":
            return "需要用关系词连接被修饰名词和后面的说明，避免把两个句子直接拼在一起。"
        case "时间介词":
            return "表示从过去某个时间点开始持续到现在时，常用 since；表示一段时间常用 for。"
        default:
            return "先保证主语、谓语和宾语顺序清晰，再检查目标语法点。"
        }
    }

    private func nextSimilarQuestion(for skill: GrammarSkill) -> String {
        switch skill.name {
        case "现在完成时":
            return "我已经练习听力两周了。"
        case "定语从句":
            return "这是我最喜欢的那部电影。"
        case "时间介词":
            return "她已经在这家公司工作五年了。"
        case "to do 作目的":
            return "他早起是为了赶第一班车。"
        default:
            return "我想用更清楚的方式表达这个观点。"
        }
    }
}
