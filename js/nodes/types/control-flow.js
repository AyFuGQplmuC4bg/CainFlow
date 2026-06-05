/**
 * Defines logic control node metadata, ports and default sizes.
 */
export const controlConditionNode = {
    type: 'ControlCondition',
    title: '条件判断',
    cssClass: 'node-control node-control-condition',
    icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3v6"/><path d="M6 15v6"/><path d="M18 3v6"/><path d="M18 15v6"/><path d="M6 9a6 6 0 0 0 6 6h6"/><path d="M18 9a6 6 0 0 1-6 6H6"/></svg>',
    inputs: [
        { name: 'value', type: 'text', label: '判断值' },
        { name: 'compare', type: 'text', label: '比较值' }
    ],
    outputs: [
        { name: 'true', type: 'text', label: '是' },
        { name: 'false', type: 'text', label: '否' }
    ],
    defaultWidth: 300,
    defaultHeight: 330
};

export const controlLoopNode = {
    type: 'ControlLoop',
    title: '循环',
    cssClass: 'node-control node-control-loop',
    icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 2l4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15"/><path d="M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/></svg>',
    inputs: [
        { name: 'value', type: 'text', label: '循环输入' },
        { name: 'count', type: 'text', label: '次数' }
    ],
    outputs: [
        { name: 'loop', type: 'text', label: '循环项' },
        { name: 'done', type: 'text', label: '完成' }
    ],
    defaultWidth: 300,
    defaultHeight: 330
};
