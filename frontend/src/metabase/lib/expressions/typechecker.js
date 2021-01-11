import { ngettext, msgid } from "ttag";
import { ExpressionVisitor } from "./visitor";
import { CLAUSE_TOKENS } from "./lexer";

export function typeCheck(cst, rootType) {
  class TypeChecker extends ExpressionVisitor {
    constructor() {
      super();
      this.typeStack = [rootType];
      this.errors = [];
    }

    expression(ctx) {
      this.typeStack.unshift(rootType);
      const result = super.expression(ctx);
      this.typeStack.shift();
      return result;
    }
    aggregation(ctx) {
      this.typeStack.unshift("aggregation");
      const result = super.aggregation(ctx);
      this.typeStack.shift();
      return result;
    }
    boolean(ctx) {
      this.typeStack.unshift("boolean");
      const result = super.boolean(ctx);
      this.typeStack.shift();
      return result;
    }

    logicalOrExpression(ctx) {
      const type = ctx.operands.length > 1 ? "boolean" : this.typeStack[0];
      this.typeStack.unshift(type);
      const result = super.logicalOrExpression(ctx);
      this.typeStack.shift();
      return result;
    }
    logicalAndExpression(ctx) {
      const type = ctx.operands.length > 1 ? "boolean" : this.typeStack[0];
      this.typeStack.unshift(type);
      const result = super.logicalAndExpression(ctx);
      this.typeStack.shift();
      return result;
    }
    logicalNotExpression(ctx) {
      this.typeStack.unshift("boolean");
      const result = super.logicalNotExpression(ctx);
      this.typeStack.shift();
      return result;
    }
    relationalExpression(ctx) {
      const type = ctx.operands.length > 1 ? "expression" : this.typeStack[0];
      this.typeStack.unshift(type);
      const result = super.relationalExpression(ctx);
      this.typeStack.shift();
      return result;
    }

    // TODO check for matching argument signature
    functionExpression(ctx) {
      const args = ctx.arguments || [];
      const functionToken = ctx.functionName[0].tokenType;
      const clause = CLAUSE_TOKENS.get(functionToken);
      const name = functionToken.name;
      const expectedArgsLength = clause.args.length;
      if (!clause.multiple && clause.args.length !== args.length) {
        const message = ngettext(
          msgid`Function ${name} expects ${expectedArgsLength} argument`,
          `Function ${name} expects ${expectedArgsLength} arguments`,
          expectedArgsLength,
        );
        this.errors.push({ message });
      }
      return args.map(arg => {
        this.typeStack.unshift("expression");
        const result = this.visit(arg);
        this.typeStack.unshift();
        return result;
      });
    }

    dimensionExpression(ctx) {
      const type = this.typeStack[0];
      if (type === "aggregation") {
        ctx.resolveAs = "metric";
      } else if (type === "boolean") {
        ctx.resolveAs = "segment";
      } else {
        ctx.resolveAs = "dimension";
        if (type === "aggregation") {
          throw new Error("Incorrect type for dimension");
        }
      }
      return super.dimensionExpression(ctx);
    }
  }
  const checker = new TypeChecker();
  checker.visit(cst);
  return { typeErrors: checker.errors };
}